function Optimize-MP4 {
    param(
        [string]$OutputDir = "cleaned"
    )

    $InputDir = Get-Location
    $OutputPath = Join-Path $InputDir $OutputDir

    # Создать папку назначения
    if (!(Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath | Out-Null
    }

    # Найти MP4
    $files = Get-ChildItem -Path $InputDir -Filter "*.mp4" -File

    if ($files.Count -eq 0) {
        Write-Host "MP4 файлов не найдено." -ForegroundColor Yellow
        return
    }

    foreach ($file in $files) {

        $destination = Join-Path $OutputPath $file.Name

        Write-Host ""
        Write-Host "Обработка: $($file.Name)" -ForegroundColor Cyan

        if (Test-Path $destination) {
            Write-Host "Пропуск (уже существует): $destination" -ForegroundColor Yellow
            continue
        }

        & ffmpeg `
            -hide_banner `
            -loglevel warning `
            -i $file.FullName `
            -map 0 `
            -c copy `
            -map_metadata -1 `
            -movflags +faststart `
            $destination

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Готово: $destination" -ForegroundColor Green
        }
        else {
            Write-Host "Ошибка: $($file.Name)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "Очистка завершена." -ForegroundColor Green
}