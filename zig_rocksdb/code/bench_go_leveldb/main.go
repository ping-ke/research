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
)

const (
	valLen = 110
	keyLen = 32
)

var (
	ni       = flag.Bool("needInit", false, "Need to insert kvs before test, default false")
	tc       = flag.Int64("total", 4000000000, "Number of kvs to insert before test, default value is 4_000_000_000")
	wc       = flag.Int64("write", 1000000, "Number of write count during the test")
	rc       = flag.Int64("read", 1000000, "Number of read count during the test")
	t        = flag.Int64("thread", 8, "Number of threads")
	dbPath   = flag.String("dbpath", "./bench_go_leveldb", "Data directory for the databases")
	logLevel = flag.Int64("loglevel", 3, "Log level")
)

var (
	randBytes = make([]byte, valLen*keyLen)
)

func randomWrite(tid, count, start, end int64, db *leveldb.DB, wg *sync.WaitGroup) {
	wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	val := make([]byte, valLen)
	for i := int64(0); i < count; i++ {
		rv := rand.Int63n(end-start) + start
		s := (rv % keyLen) * valLen
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(rv))
		copy(val, randBytes[s:s+valLen])
		db.Put(key, val, nil)
		if *logLevel >= 3 && i%100000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Microseconds()
	fmt.Printf("thread %d written done used time %d ms, hps %d \n", tid, tu, count*1000000/tu)
}

func randomRead(tid, count, start, end int64, db *leveldb.DB, wg *sync.WaitGroup) {
	wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	for i := int64(0); i < count; i++ {
		rv := rand.Int63n(end-start) + start
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(rv))
		_, _ = db.Get(key, nil)
		if *logLevel >= 3 && i%100000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Microseconds()
	fmt.Printf("thread %d written done used time %d ms, hps %d \n", tid, tu, count*1000000/tu)
}

func seqWrite(tid, count int64, db *leveldb.DB, wg *sync.WaitGroup) {
	wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	val := make([]byte, valLen)
	for i := int64(0); i < count; i++ {
		idx := tid*count + i
		s := (idx % keyLen) * valLen
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(idx))
		copy(val, randBytes[s:s+valLen])
		db.Put(key, val, nil)
		if *logLevel >= 3 && i%100000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Microseconds()
	fmt.Printf("thread %d written done used time %d ms, hps %d \n", tid, tu, count*1000000/tu)
}

func seqRead(tid, count int64, db *leveldb.DB, wg *sync.WaitGroup) {
	wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	for i := int64(0); i < count; i++ {
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(tid*count+i))
		_, _ = db.Get(key, nil)
		if *logLevel >= 3 && i%100000 == 0 && i > 0 {
			ms := time.Since(st).Microseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", tid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Milliseconds()
	fmt.Printf("thread %d written done used time %d ms, hps %d \n", tid, tu, count*1000000/tu)
}

func main() {
	flag.Parse()

	db, err := leveldb.OpenFile(*dbPath, nil)
	if err != nil {
		log.Fatal(err)
	}
	defer func() {
		if db != nil {
			err := db.Close()
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
			go seqWrite(tid, per, db, &wg)
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
			go randomWrite(tid, per, 0, total, db, &wg)
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
			go randomRead(tid, per, 0, total, db, &wg)
		}
		wg.Wait()
		ms := float64(time.Since(start).Milliseconds())
		fmt.Printf("Random read: %d ops in %.2f ms (%.2f ops/s)\n", readCount, ms, float64(readCount)*1000/ms)
	}
}
