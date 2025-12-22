package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"flag"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/cockroachdb/pebble"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	jsonrpc "github.com/ybbus/jsonrpc/v3"
)

var (
	clientStr    = flag.String("client", "http://jrpc.mainnet.quarkchain.io:38391", "client url")
	dbPath       = flag.String("p", "./data/bench_pebble", "Data directory for the databases")
)

type Stats struct {
	DailyAU     map[string]map[common.Address]struct{}
	MonthlyAU   map[string]map[common.Address]struct{}
	QuarterlyAU map[string]map[common.Address]struct{}

	DailyTx     map[string]uint64
	MonthlyTx   map[string]uint64
	QuarterlyTx map[string]uint64
}

func (s *Stats) String() string {
	lock.Lock()
	defer lock.Unlock()
	str := "Daily======================\nDate\tActiveUser\tTxCount\n"
	for date, adds := range s.DailyAU {
		str = str + fmt.Sprintf("%s\t%d\t%d\n", date, len(adds), s.DailyTx[date])
	}
	str = str + "Monthly====================\n"
	for date, adds := range s.MonthlyAU {
		str = str + fmt.Sprintf("%s\t%d\t%d\n", date, len(adds), s.MonthlyTx[date])
	}
	str = str + "3 Months===================\n"
	for date, adds := range s.QuarterlyAU {
		str = str + fmt.Sprintf("%s\t%d\t%d\n", date, len(adds), s.QuarterlyTx[date])
	}
	return str
}

var (
	lock         sync.Mutex
	startNumbers = []uint64{20137500, 20064700, 20107300, 20168800, 20206960, 20109970, 20036520, 20023480}
)

func main() {
	flag.Parse()

	client := jsonrpc.NewClient(*clientStr)

	db, err := pebble.Open(*dbPath, &pebble.Options{})
	if err != nil {
		panic(err)
	}
	defer db.Close()

	stats, err := LoadAllStatsFromDaily(db)
	if err != nil {
		panic(err)
	}

	go func() {
		fmt.Print(stats.String())
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				fmt.Print(stats.String())
			}
		}
	}()

	shards := []int{0, 1, 2, 3, 4, 5, 6, 7}
	var wg sync.WaitGroup

	for _, shardID := range shards {
		wg.Add(1)
		go func(sid int) {
			defer wg.Done()
			processShard(db, client, stats, sid)
		}(shardID)
	}

	wg.Wait()
}

func processShard(db *pebble.DB, client jsonrpc.RPCClient, stats *Stats, shardID int) {
	for {
		lastBlock := loadLastBlock(db, shardID)
		if lastBlock == 0 {
			lastBlock = startNumbers[shardID]
		}

		latest := getLatestBlock(client, shardID)
		if latest == 0 {
			continue
		}

		if lastBlock >= latest {
			time.Sleep(5 * time.Second)
			continue
		}

		for bn := lastBlock + 1; bn <= latest; bn++ {
			processBlock(db, client, stats, shardID, bn)
			saveLastBlock(db, shardID, bn)
		}
	}
}

func processBlock(
	db *pebble.DB,
	client jsonrpc.RPCClient,
	stats *Stats,
	shardID int,
	blockNum uint64,
) {
	resp, err := client.Call(
		context.Background(),
		"getMinorBlockByHeight",
		hexutil.EncodeUint64(uint64(shardID<<16)),
		hexutil.EncodeUint64(blockNum),
		true,
		false,
	)
	if err != nil || resp.Error != nil || resp.Result == nil {
		return
	}

	block := resp.Result.(map[string]interface{})
	tsHex := block["timestamp"].(string)
	ts, _ := hexutil.DecodeUint64(tsHex)

	blockTime := time.Unix(int64(ts), 0)

	date := blockTime.Format("2006-01-02")
	month := blockTime.Format("2006-01")
	monthPlusOne := blockTime.AddDate(0, 1, 0).Format("2006-01")
	monthPlusTwo := blockTime.AddDate(0, 2, 0).Format("2006-01")

	txs := block["transactions"].([]interface{})
	if len(txs) == 0 {
		return
	}

	if _, ok := stats.DailyAU[date]; !ok {
		stats.DailyAU[date] = make(map[common.Address]struct{})
		stats.DailyTx[date] = 0
	}
	if _, ok := stats.MonthlyAU[month]; !ok {
		stats.MonthlyAU[month] = make(map[common.Address]struct{})
		stats.QuarterlyAU[month] = make(map[common.Address]struct{})
		stats.MonthlyTx[month] = 0
		stats.QuarterlyTx[month] = 0
	}
	if _, ok := stats.QuarterlyAU[monthPlusOne]; !ok {
		stats.QuarterlyAU[monthPlusOne] = make(map[common.Address]struct{})
		stats.QuarterlyTx[monthPlusOne] = 0
	}
	if _, ok := stats.QuarterlyAU[monthPlusTwo]; !ok {
		stats.QuarterlyAU[monthPlusTwo] = make(map[common.Address]struct{})
		stats.QuarterlyTx[monthPlusTwo] = 0
	}

	// ---- active users ----
	for _, tx := range txs {
		from := common.HexToAddress(tx.(map[string]interface{})["from"].(string))
		key := fmt.Sprintf("daily:au:%s:%s", date, from.Hex())
		db.Set([]byte(key), []byte{1}, pebble.NoSync)
		stats.DailyAU[date][from] = struct{}{}
		stats.MonthlyAU[month][from] = struct{}{}
		stats.QuarterlyAU[month][from] = struct{}{}
		stats.QuarterlyAU[monthPlusOne][from] = struct{}{}
		stats.QuarterlyAU[monthPlusTwo][from] = struct{}{}
	}
	lock.Lock()
	stats.DailyTx[date] += uint64(len(txs))
	stats.MonthlyTx[month] += uint64(len(txs))
	stats.QuarterlyTx[month] += uint64(len(txs))
	stats.QuarterlyTx[monthPlusOne] += uint64(len(txs))
	stats.QuarterlyTx[monthPlusTwo] += uint64(len(txs))
	lock.Unlock()
	key := fmt.Sprintf("daily:cnt:%s", date)
	val := make([]byte, 8, 8)
	binary.BigEndian.PutUint64(val, stats.DailyTx[date])
	db.Set([]byte(key), val, pebble.NoSync)
}

func loadLastBlock(db *pebble.DB, shardID int) uint64 {
	key := []byte(fmt.Sprintf("last:block:%d", shardID))

	val, closer, err := db.Get(key)
	if err != nil {
		if err == pebble.ErrNotFound {
			return 0
		}
		log.Fatalf("loadLastBlock shard=%d err=%v", shardID, err)
	}
	defer closer.Close()

	return binary.BigEndian.Uint64(val)
}

func saveLastBlock(db *pebble.DB, shardID int, bn uint64) {
	key := []byte(fmt.Sprintf("last:block:%d", shardID))

	buf := make([]byte, 8)
	binary.BigEndian.PutUint64(buf, bn)

	if err := db.Set(key, buf, pebble.Sync); err != nil {
		log.Fatalf("saveLastBlock shard=%d bn=%d err=%v", shardID, bn, err)
	}
}

func getLatestBlock(client jsonrpc.RPCClient, shardID int) uint64 {
	resp, err := client.Call(
		context.Background(),
		"getMinorBlockByHeight",
		hexutil.EncodeUint64(uint64(shardID<<16)),
		nil,
		true,
		false,
	)
	if err != nil || resp.Error != nil || resp.Result == nil {
		log.Printf("getLatestBlock shard=%d rpc error: %v respErr=%v", shardID, err, resp.Error)
		return 0
	}

	block, ok := resp.Result.(map[string]interface{})
	if !ok {
		log.Printf("getLatestBlock shard=%d invalid result type", shardID)
		return 0
	}

	numHex, ok := block["height"].(string)
	if !ok {
		log.Printf("getLatestBlock shard=%d missing number field", shardID)
		return 0
	}

	num, err := hexutil.DecodeUint64(numHex)
	if err != nil {
		log.Printf("getLatestBlock shard=%d decode number failed: %v", shardID, err)
		return 0
	}

	return num
}

func LoadAllStatsFromDaily(db *pebble.DB) (*Stats, error) {
	stats := &Stats{
		DailyAU:     make(map[string]map[common.Address]struct{}),
		MonthlyAU:   make(map[string]map[common.Address]struct{}),
		QuarterlyAU: make(map[string]map[common.Address]struct{}),

		DailyTx:     make(map[string]uint64),
		MonthlyTx:   make(map[string]uint64),
		QuarterlyTx: make(map[string]uint64),
	}

	// 1️⃣ load daily active users
	if err := loadDailyAUAndAggregate(db, stats); err != nil {
		return nil, err
	}

	// 2️⃣ load daily tx count
	if err := loadDailyTxAndAggregate(db, stats); err != nil {
		return nil, err
	}

	return stats, nil
}

func loadDailyAUAndAggregate(db *pebble.DB, stats *Stats) error {
	prefix := []byte("daily:au:")

	iter, err := db.NewIter(&pebble.IterOptions{
		LowerBound: prefix,
		UpperBound: append(prefix, 0xff),
	})
	defer iter.Close()
	if err != nil {
		return err
	}

	for iter.First(); iter.Valid(); iter.Next() {
		key := iter.Key()
		// daily:au:YYYY-MM-DD:0xaddr
		parts := bytes.Split(key, []byte(":"))
		if len(parts) != 4 {
			continue
		}

		dateStr := string(parts[2])
		addr := common.HexToAddress(string(parts[3]))

		t, err := time.Parse("2006-01-02", dateStr)
		if err != nil {
			continue
		}

		month := t.Format("2006-01")
		monthPlusOne := t.AddDate(0, 1, 0).Format("2006-01")
		monthPlusTwo := t.AddDate(0, 2, 0).Format("2006-01")

		// ---- daily ----
		if _, ok := stats.DailyAU[dateStr]; !ok {
			stats.DailyAU[dateStr] = make(map[common.Address]struct{})
		}
		stats.DailyAU[dateStr][addr] = struct{}{}

		// ---- monthly ----
		if _, ok := stats.MonthlyAU[month]; !ok {
			stats.MonthlyAU[month] = make(map[common.Address]struct{})
			stats.QuarterlyAU[month] = make(map[common.Address]struct{})
		}
		stats.MonthlyAU[month][addr] = struct{}{}
		stats.QuarterlyAU[month][addr] = struct{}{}

		if _, ok := stats.QuarterlyAU[monthPlusOne]; !ok {
			stats.QuarterlyAU[monthPlusOne] = make(map[common.Address]struct{})
		}
		stats.QuarterlyAU[monthPlusOne][addr] = struct{}{}

		if _, ok := stats.QuarterlyAU[monthPlusTwo]; !ok {
			stats.QuarterlyAU[monthPlusTwo] = make(map[common.Address]struct{})
		}
		stats.QuarterlyAU[monthPlusTwo][addr] = struct{}{}
	}

	return iter.Error()
}

func loadDailyTxAndAggregate(db *pebble.DB, stats *Stats) error {
	prefix := []byte("daily:cnt:")

	iter, err := db.NewIter(&pebble.IterOptions{
		LowerBound: prefix,
		UpperBound: append(prefix, 0xff),
	})
	defer iter.Close()
	if err != nil {
		return err
	}

	for iter.First(); iter.Valid(); iter.Next() {
		key := string(iter.Key()) // daily:cnt:YYYY-MM-DD
		dateStr := key[len("daily:cnt:"):]

		val := iter.Value()
		if len(val) != 8 {
			continue
		}
		cnt := binary.BigEndian.Uint64(val)

		t, err := time.Parse("2006-01-02", dateStr)
		if err != nil {
			continue
		}

		month := t.Format("2006-01")
		monthPlusOne := t.AddDate(0, 1, 0).Format("2006-01")
		monthPlusTwo := t.AddDate(0, 2, 0).Format("2006-01")

		stats.DailyTx[dateStr] += cnt
		stats.MonthlyTx[month] += cnt
		stats.QuarterlyTx[month] += cnt
		stats.QuarterlyTx[monthPlusOne] += cnt
		stats.QuarterlyTx[monthPlusTwo] += cnt
	}

	return iter.Error()
}
