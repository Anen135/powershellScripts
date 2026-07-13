param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile
)

if (!(Test-Path $InputFile)) {
    Write-Host "Файл не найден: $InputFile" -ForegroundColor Red
    exit 1
}

if (!(Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    Write-Host "ffprobe не найден." -ForegroundColor Red
    exit 1
}

$OutputFile = [System.IO.Path]::ChangeExtension($InputFile, ".analysis.txt")

function Step($text) {
    Write-Host ""
    Write-Host "[*] $text [$((Get-Date).TimeOfDay)]" -ForegroundColor Cyan
}

function Run-Probe($ProbeArgs, $section) {
    Step $section

    $start = Get-Date

    & ffprobe @ProbeArgs 2>> $null |
        Out-File $OutputFile -Append

    $time = (Get-Date) - $start

    Write-Host "    Готово за $([math]::Round($time.TotalSeconds,2)) сек." -ForegroundColor Green
}


Remove-Item $OutputFile -ErrorAction SilentlyContinue


"======================================" | Out-File $OutputFile
"FFmpeg MP4 ANALYSIS REPORT" | Out-File $OutputFile -Append
"File: $InputFile" | Out-File $OutputFile -Append
"Date: $(Get-Date)" | Out-File $OutputFile -Append
"======================================" | Out-File $OutputFile -Append


Run-Probe @(
    "-v","error",
    "-show_entries",
    "format=filename,format_name,duration,size,bit_rate",
    "-of",
    "default=noprint_wrappers=1",
    $InputFile
) "Общая информация"


Run-Probe @(
    "-v","error",
    "-show_entries",
    "stream=index,codec_type,codec_name,profile,level,width,height,pix_fmt,r_frame_rate,avg_frame_rate,bit_rate,channels,sample_rate",
    "-of",
    "default=noprint_wrappers=1",
    $InputFile
) "Информация о потоках"


Run-Probe @(
    "-v","error",
    "-select_streams","v:0",
    "-show_entries","stream",
    "-of","default=noprint_wrappers=1",
    $InputFile
) "Видео поток"


Run-Probe @(
    "-v","error",
    "-select_streams","a:0",
    "-show_entries","stream",
    "-of","default=noprint_wrappers=1",
    $InputFile
) "Аудио поток"


Step "Подсчёт ключевых кадров"

$start = Get-Date

$keyFrames = ffprobe `
    -select_streams v:0 `
    -show_frames `
    -show_entries frame=pict_type `
    -of csv `
    $InputFile |
    Select-String ",I"

$elapsed = (Get-Date) - $start

"=== KEY FRAMES ===" | Out-File $OutputFile -Append
"Key frames count: $($keyFrames.Count)" | Out-File $OutputFile -Append

Write-Host "    Ключевых кадров: $($keyFrames.Count)"
Write-Host "    Время: $([math]::Round($elapsed.TotalSeconds,2)) сек." -ForegroundColor Green


Run-Probe @(
    "-v","error",
    "-show_entries",
    "stream=index,codec_type,codec_name",
    "-of","table",
    $InputFile
) "Проверка всех потоков"


Write-Host ""
Write-Host "================================="
Write-Host "Анализ завершён" -ForegroundColor Green
Write-Host "Файл отчёта:"
Write-Host $OutputFile