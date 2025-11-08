package main

import (
	"encoding/binary"
	"flag"
	"fmt"
	"math/rand"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethdb"
	"github.com/ethereum/go-ethereum/ethdb/leveldb"
	"github.com/ethereum/go-ethereum/ethdb/pebble"
	"github.com/ethereum/go-ethereum/log"
)

const (
	valLen = 110
	keyLen = 32
)

var (
	ni       = flag.Bool("needInit", false, "Need to insert kvs before test, default false")
	tc       = flag.Int64("total", 4000000000, "Number of kvs to insert before test, default value is 4_000_000_000")
	wc       = flag.Int64("write", 10000000, "Number of write count during the test")
	rc       = flag.Int64("read", 10000000, "Number of read count during the test")
	bi       = flag.Bool("batchInsert", true, "Enable batch insert or not")
	t        = flag.Int64("threads", 32, "Number of threads")
	dbtype   = flag.String("dbtype", "leveldb", "The db type: leveldb, pebble")
	dbPath   = flag.String("dbpath", "./data/bench_go_eth_leveldb", "Data directory for the databases")
	logLevel = flag.Int64("loglevel", 3, "Log level")
)

var (
	randBytes = make([]byte, valLen*keyLen)
)

func hash(sha crypto.KeccakState, in []byte) []byte {
	sha.Reset()
	sha.Write(in)
	h := make([]byte, 32)
	sha.Read(h)
	return h
}

func randomWrite(tid, count, start, end int64, db ethdb.KeyValueWriter, wg *sync.WaitGroup) {
	defer wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	r := rand.New(rand.NewSource(time.Now().UnixNano() + tid))
	sha := crypto.NewKeccakState()
	for i := int64(0); i < count; i++ {
		rv := r.Int63n(end-start) + start
		s := (rv % keyLen) * valLen
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(rv))
		k := hash(sha, key)
		_ = db.Put(k, randBytes[s:s+valLen])
		if *logLevel >= 3 && i%1000000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	if *logLevel >= 3 {
		tu := time.Since(st).Seconds()
		fmt.Printf("thread %d random write done %.2fs, %.2f ops/s\n", tid, tu, float64(count)/tu)
	}
}

func randomRead(tid int64, keys [][]byte, db ethdb.KeyValueReader, wg *sync.WaitGroup) {
	defer wg.Done()
	st := time.Now()
	i := int64(0)

	for _, key := range keys {
		_, _ = db.Get(key)
		if *logLevel >= 3 && i%1000000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
		i++
	}
	if *logLevel >= 3 {
		tu := time.Since(st).Seconds()
		fmt.Printf("thread %d random read done %.2fs, %.2f ops/s\n", tid, tu, float64(len(keys))/tu)
	}
}

func batchWrite(tid, count int64, db ethdb.Batcher, wg *sync.WaitGroup) {
	defer wg.Done()
	st := time.Now()
	sha := crypto.NewKeccakState()
	key := make([]byte, keyLen)
	batch := db.NewBatch()
	for i := int64(0); i < count; i++ {
		idx := tid*count + i
		s := (idx % keyLen) * valLen
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(idx))
		k := hash(sha, key)
		batch.Put(k, randBytes[s:s+valLen])

		if i%1000 == 0 {
			_ = batch.Write()
			batch.Reset()
		} else {
			continue
		}
		if *logLevel >= 3 && i%1000000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	if batch.ValueSize() > 0 {
		_ = batch.Write()
	}
	if *logLevel >= 3 {
		tu := time.Since(st).Seconds()
		fmt.Printf("thread %d batch write done %.2fs, %.2f ops/s\n", tid, tu, float64(count)/tu)
	}
}

func seqWrite(tid, count int64, db ethdb.KeyValueWriter, wg *sync.WaitGroup) {
	defer wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	for i := int64(0); i < count; i++ {
		idx := tid*count + i
		s := (idx % keyLen) * valLen
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(idx))
		_ = db.Put(key, randBytes[s:s+valLen])
		if *logLevel >= 3 && i%1000000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	if *logLevel >= 3 {
		tu := time.Since(st).Seconds()
		fmt.Printf("thread %d seq write done %.2fs, %.2f ops/s\n", tid, tu, float64(count)/tu)
	}
}

func seqRead(tid, count int64, db ethdb.KeyValueReader, wg *sync.WaitGroup) {
	defer wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	for i := int64(0); i < count; i++ {
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(tid*count+i))
		_, _ = db.Get(key)
		if *logLevel >= 3 && i%1000000 == 0 && i > 0 {
			ms := time.Since(st).Microseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	if *logLevel >= 3 {
		tu := time.Since(st).Seconds()
		fmt.Printf("thread %d seq read done %.2fs, %.2f ops/s\n", tid, tu, float64(count)/tu)
	}
}

func main() {
	flag.Parse()

	var (
		db  ethdb.KeyValueStore
		err error
	)

	if *dbtype == "leveldb" {
		db, err = leveldb.New(*dbPath, 512, 100000, "bench_go_eth_leveldb", false)
	} else {
		db, err = pebble.New("./data/bench_go_eth_pebble", 512, 100000, "bench_go_eth_pebble", false)
	}

	if err != nil {
		log.Crit("New dashboard fail", "err", err)
	} else {
		defer db.Close()
	}

	threads := *t
	total := *tc
	writeCount := *wc
	readCount := *rc
	fmt.Printf("Threads: %d\n", threads)
	fmt.Printf("Total data: %d while needInit=%t\n", total, *ni)
	fmt.Printf("Ops: %d write ops and %d read ops\n", writeCount, readCount)

	rand.Read(randBytes)

	var wg sync.WaitGroup
	if *ni && total > 0 {
		start := time.Now()
		per := total / threads
		for tid := int64(0); tid < threads; tid++ {
			wg.Add(1)
			id := tid
			if *bi {
				go batchWrite(id, per, db, &wg)
			} else {
				go seqWrite(id, per, db, &wg)
			}
		}
		wg.Wait()
		ms := float64(time.Since(start).Milliseconds())
		fmt.Printf("Init write: %d ops in %.2f ms (%.2f ops/s)\n", total, ms, float64(total)*1000/ms)
	}

	if writeCount > 0 {
		start := time.Now()
		per := writeCount / threads
		for tid := int64(0); tid < threads; tid++ {
			wg.Add(1)
			id := tid
			go randomWrite(id, per, 0, total, db, &wg)
		}
		wg.Wait()
		ms := float64(time.Since(start).Milliseconds())
		fmt.Printf("Random update: %d ops in %.2f ms (%.2f ops/s)\n", writeCount, ms, float64(writeCount)*1000/ms)
	}

	if readCount > 0 {
		r := rand.New(rand.NewSource(time.Now().UnixNano()))
		thread_keys := make([][][]byte, threads)
		per := readCount / threads

		for i := int64(0); i < threads; i++ {
			keys := make([][]byte, per)
			sha := crypto.NewKeccakState()
			for j := int64(0); j < per; j++ {
				rv := r.Int63n(total)
				key := make([]byte, keyLen)
				binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(rv))
				k := hash(sha, key)
				keys[j] = k
			}
			thread_keys[i] = keys
		}

		start := time.Now()
		for tid := int64(0); tid < threads; tid++ {
			wg.Add(1)
			id := tid
			keys := thread_keys[id]
			go randomRead(id, keys, db, &wg)
		}
		wg.Wait()
		ms := float64(time.Since(start).Milliseconds())
		fmt.Printf("Random read: %d ops in %.2f ms (%.2f ops/s)\n", readCount, ms, float64(readCount)*1000/ms)
		s, _ := db.Stat()
		fmt.Printf("Random Read stat \n%s", s)
	}
}
