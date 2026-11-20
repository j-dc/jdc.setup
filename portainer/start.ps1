$composeFile = Join-Path $PSScriptRoot 'compose.yaml'

docker compose -f $composeFile pull
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

docker compose -f $composeFile up -d
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
