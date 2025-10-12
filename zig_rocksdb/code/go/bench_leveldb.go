package main

import (
	"crypto/rand"
	"fmt"
	"log"
	"os"
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
		dbPath      = "leveldb_bench"
		totalKeys   = 100000
		sampleReads = 10000
	)

	_ = os.RemoveAll(dbPath)
	db, err := leveldb.OpenFile(dbPath, nil)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	fmt.Printf("Starting LevelDB test (32B key, 110B value)\n")

	// 写入
	start := time.Now()
	for i := 0; i < totalKeys; i++ {
		key := randomBytes(32)
		value := randomBytes(110)
		if err := db.Put(key, value, nil); err != nil {
			log.Fatal(err)
		}
	}
	writeMs := float64(time.Since(start).Milliseconds())
	fmt.Printf("Write: %d ops in %.2f ms (%.2f ops/s)\n", totalKeys, writeMs, float64(totalKeys)*1000/writeMs)

	// 读取
	start = time.Now()
	for i := 0; i < sampleReads; i++ {
		key := randomBytes(32)
		_, _ = db.Get(key, nil)
	}
	readMs := float64(time.Since(start).Milliseconds())
	fmt.Printf("Read: %d ops in %.2f ms (%.2f ops/s)\n", sampleReads, readMs, float64(sampleReads)*1000/readMs)
}
