package main

import (
	"crypto/rand"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"github.com/syndtr/goleveldb/leveldb"
)

func randomBytes(n int) []byte {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return b
}

func main() {
	const (
		dbPath      = "leveldb_mt"
		totalKeys   = 100000
		sampleReads = 10000
		threadCount = 8
	)

	_ = os.RemoveAll(dbPath)
	db, err := leveldb.OpenFile(dbPath, nil)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	fmt.Printf("Threads: %d\n", threadCount)

	// ---- 写入 ----
	start := time.Now()
	var wg sync.WaitGroup
	per := totalKeys / threadCount
	for t := 0; t < threadCount; t++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < per; i++ {
				key := randomBytes(32)
				val := randomBytes(110)
				_ = db.Put(key, val, nil)
			}
		}()
	}
	wg.Wait()
	writeMs := float64(time.Since(start).Milliseconds())
	fmt.Printf("Write: %d ops in %.2f ms (%.2f ops/s)\n", totalKeys, writeMs, float64(totalKeys)*1000/writeMs)

	// ---- 读取 ----
	start = time.Now()
	perR := sampleReads / threadCount
	wg = sync.WaitGroup{}
	for t := 0; t < threadCount; t++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < perR; i++ {
				key := randomBytes(32)
				_, _ = db.Get(key, nil)
			}
		}()
	}
	wg.Wait()
	readMs := float64(time.Since(start).Milliseconds())
	fmt.Printf("Read: %d ops in %.2f ms (%.2f ops/s)\n", sampleReads, readMs, float64(sampleReads)*1000/readMs)
}
