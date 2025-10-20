package main

import (
	"encoding/binary"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"sync"
	"time"

	"github.com/syndtr/goleveldb/leveldb"
	"github.com/syndtr/goleveldb/leveldb/opt"
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
	t        = flag.Int64("thread", 8, "Number of threads")
	bi       = flag.Bool("batchInsert", true, "Enable batch insert or not")
	dbPath   = flag.String("dbpath", "./data/bench_go_leveldb", "Data directory for the databases")
	logLevel = flag.Int64("loglevel", 3, "Log level")
)

var (
	randBytes = make([]byte, valLen*keyLen)
)

func randomWrite(tid, count, start, end int64, db *leveldb.DB, wg *sync.WaitGroup) {
	defer wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	r := rand.New(rand.NewSource(time.Now().UnixNano() + tid))
	for i := int64(0); i < count; i++ {
		rv := r.Int63n(end-start) + start
		s := (rv % keyLen) * valLen
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(rv))
		_ = db.Put(key, randBytes[s:s+valLen], nil)
		if *logLevel >= 3 && i%1000000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Seconds()
	fmt.Printf("thread %d random write done %.2fs, %.2f ops/s\n", tid, tu, float64(count)/tu)
}

func randomRead(tid, count, start, end int64, db *leveldb.DB, wg *sync.WaitGroup) {
	defer wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	r := rand.New(rand.NewSource(time.Now().UnixNano() + tid))
	for i := int64(0); i < count; i++ {
		rv := r.Int63n(end-start) + start
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(rv))
		_, _ = db.Get(key, nil)
		if *logLevel >= 3 && i%1000000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Seconds()
	fmt.Printf("thread %d random read done %.2fs, %.2f ops/s\n", tid, tu, float64(count)/tu)
}

func batchWrite(tid, count int64, db *leveldb.DB, wg *sync.WaitGroup) {
	defer wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	batch := new(leveldb.Batch)
	for i := int64(0); i < count; i++ {
		idx := tid*count + i
		s := (idx % keyLen) * valLen
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(idx))
		batch.Put(key, randBytes[s:s+valLen])

		if i%1000 == 0 {
			_ = db.Write(batch, nil)
			batch.Reset()
		} else {
			continue
		}
		if *logLevel >= 3 && i%1000000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	if batch.Len() > 0 {
		_ = db.Write(batch, nil)
	}
	tu := time.Since(st).Seconds()
	fmt.Printf("thread %d batch write done %.2fs, %.2f ops/s\n", tid, tu, float64(count)/tu)
}

func seqWrite(tid, count int64, db *leveldb.DB, wg *sync.WaitGroup) {
	defer wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	for i := int64(0); i < count; i++ {
		idx := tid*count + i
		s := (idx % keyLen) * valLen
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(idx))
		_ = db.Put(key, randBytes[s:s+valLen], nil)
		if *logLevel >= 3 && i%1000000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Seconds()
	fmt.Printf("thread %d seq write done %.2fs, %.2f ops/s\n", tid, tu, float64(count)/tu)
}

func seqRead(tid, count int64, db *leveldb.DB, wg *sync.WaitGroup) {
	defer wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	for i := int64(0); i < count; i++ {
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(tid*count+i))
		_, _ = db.Get(key, nil)
		if *logLevel >= 3 && i%1000000 == 0 && i > 0 {
			ms := time.Since(st).Microseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}

	tu := time.Since(st).Seconds()
	fmt.Printf("thread %d seq read done %.2fs, %.2f ops/s\n", tid, tu, float64(count)/tu)
}

func main() {
	flag.Parse()

	opts := &opt.Options{
		Compression:            opt.NoCompression,
		BlockCacheCapacity:     128 << 20, // 128MB
		WriteBuffer:            64 << 20,  // 64MB
		CompactionTableSize:    32 << 20,  // 32MB
		CompactionTotalSize:    256 << 20, // 256MB
		OpenFilesCacheCapacity: 512,
	}
	db, err := leveldb.OpenFile(*dbPath, opts)

	if err != nil {
		log.Fatal(err)
	}
	defer func() {
		if db != nil {
			err = db.Close()
			if err != nil {
				fmt.Printf("close db err %s\n", err)
			}
		}
	}()

	threads := *t
	total := *tc
	writeCount := *wc
	readCount := *rc
	fmt.Printf("Threads: %d\n", threads)
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
		start := time.Now()
		per := readCount / threads
		for tid := int64(0); tid < threads; tid++ {
			wg.Add(1)
			id := tid
			go randomRead(id, per, 0, total, db, &wg)
		}
		wg.Wait()
		ms := float64(time.Since(start).Milliseconds())
		fmt.Printf("Random read: %d ops in %.2f ms (%.2f ops/s)\n", readCount, ms, float64(readCount)*1000/ms)
	}
}
