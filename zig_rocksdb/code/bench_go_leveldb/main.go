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

func randomWrite(thid, count, start, end int64, db *leveldb.DB, wg *sync.WaitGroup) {
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
			fmt.Printf("thread %d used time %d ms, hps %d\n", thid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Milliseconds()
	fmt.Printf("thread %d written done used time %d ms, hps %d \n", thid, tu, count*1000/tu)
}

func randomRead(thid, count, start, end int64, db *leveldb.DB, wg *sync.WaitGroup) {
	wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	for i := int64(0); i < count; i++ {
		rv := rand.Int63n(end-start) + start
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(rv))
		_, _ = db.Get(key, nil)
		if *logLevel >= 3 && i%100000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", thid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Milliseconds()
	fmt.Printf("thread %d written done used time %d ms, hps %d \n", thid, tu, count*1000/tu)
}

func seqWrite(thid, count int64, db *leveldb.DB, wg *sync.WaitGroup) {
	wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	val := make([]byte, valLen)
	for i := int64(0); i < count; i++ {
		idx := thid*count + i
		s := (idx % keyLen) * valLen
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(idx))
		copy(val, randBytes[s:s+valLen])
		db.Put(key, val, nil)
		if *logLevel >= 3 && i%100000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", thid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Milliseconds()
	fmt.Printf("thread %d written done used time %d ms, hps %d \n", thid, tu, count*1000/tu)
}

func seqRead(thid, count int64, db *leveldb.DB, wg *sync.WaitGroup) {
	wg.Done()
	st := time.Now()
	key := make([]byte, keyLen)
	for i := int64(0); i < count; i++ {
		binary.BigEndian.PutUint64(key[keyLen-8:keyLen], uint64(thid*count+i))
		_, _ = db.Get(key, nil)
		if *logLevel >= 3 && i%100000 == 0 && i > 0 {
			ms := time.Since(st).Milliseconds()
			fmt.Printf("thread %d used time %d ms, hps %d\n", thid, ms, i*1000/ms)
		}
	}
	tu := time.Since(st).Milliseconds()
	fmt.Printf("thread %d written done used time %d ms, hps %d \n", thid, tu, count*1000/tu)
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
			fmt.Printf("close db err %s\n", err)
		}
	}()

	threads := *t
	total := *tc
	writeCount := *wc
	readCount := *rc
	fmt.Printf("Threads: %d\n", threads)
	rand.Read(randBytes)

	var wg sync.WaitGroup
	if *ni {
		start := time.Now()
		per := total / threads
		for thid := int64(0); thid < threads; thid++ {
			wg.Add(1)
			go seqWrite(thid, per, db, &wg)
		}
		wg.Wait()
		writeMs := float64(time.Since(start).Milliseconds())
		fmt.Printf("Write: %d ops in %.2f ms (%.2f ops/s)\n", total, writeMs, float64(total)*1000/writeMs)
	}

	if writeCount > 0 {
		start := time.Now()
		per := writeCount / threads
		for thid := int64(0); thid < threads; thid++ {
			wg.Add(1)
			go randomWrite(thid, per, 0, total, db, &wg)
		}
		wg.Wait()
		writeMs := float64(time.Since(start).Milliseconds())
		fmt.Printf("Write: %d ops in %.2f ms (%.2f ops/s)\n", total, writeMs, float64(total)*1000/writeMs)
	}

	if readCount > 0 {
		start := time.Now()
		per := readCount / threads
		for thid := int64(0); thid < threads; thid++ {
			wg.Add(1)
			go randomRead(thid, per, 0, total, db, &wg)
		}
		wg.Wait()
		writeMs := float64(time.Since(start).Milliseconds())
		fmt.Printf("Write: %d ops in %.2f ms (%.2f ops/s)\n", total, writeMs, float64(total)*1000/writeMs)
	}
}
