@echo on

setlocal

go run main.go -t 32 -op write -n 34359738368 -r 0

for %%t in (1 4 8 16 32 64) do (
    go run main.go -t %%t -op randread -n 34359738368 -r 0
)

endlocal
exit /b 0
