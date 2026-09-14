try {
    Add-Type -AssemblyName System.Drawing
    $dstDir = "d:\xinxiangmu\shici_yaji\android\app\src\main\res\mipmap-anydpi-v26"
    $bgPath = Join-Path $dstDir "ic_launcher_background.png"
    $fgPath = Join-Path $dstDir "ic_launcher_foreground.png"
    $logPath = "d:\xinxiangmu\shici_yaji\tools\gen_icon.log"
    "" | Out-File -FilePath $logPath -Encoding utf8

    $allFamilies = [System.Drawing.FontFamily]::Families
    $allNames = @()
    foreach ($f in $allFamilies) { $allNames += $f.Name }
    $cnt = $allNames.Count
    "Families count: $cnt" | Out-File -FilePath $logPath -Append -Encoding utf8

    $fontName = "Arial"
    $kai = [char]0x6977 + [char]0x4F53   # 楷体
    $hei = [char]0x9ED1 + [char]0x4F53   # 黑体
    $song = [char]0x5B8B + [char]0x4F53  # 宋体
    $fs = [char]0x4EFF + [char]0x5B8B    # 仿宋
    $yashi = [char]0x96C5 + [char]0x9ED1  # 雅黑 (微软雅黑)
    $candidates = @($kai, $hei, $song, $fs, "KaiTi", "Microsoft YaHei", "SimHei", "Arial Unicode MS", "Arial")
    foreach ($c in $candidates) {
        if ($allNames -contains $c) { $fontName = $c; break }
    }
    "Picked font: [$fontName]" | Out-File -FilePath $logPath -Append -Encoding utf8

    # Background
    $bmp = New-Object System.Drawing.Bitmap(432, 432)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml("#F5EAD0"))
    $bmp.Save($bgPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    "OK bg: $bgPath" | Out-File -FilePath $logPath -Append -Encoding utf8

    # Foreground
    $bmp2 = New-Object System.Drawing.Bitmap(432, 432)
    $g2 = [System.Drawing.Graphics]::FromImage($bmp2)
    $g2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g2.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
    $g2.Clear([System.Drawing.Color]::Transparent)

    $poem = [char]0x8BD7   # 诗
    $ff = $allFamilies | Where-Object { $_.Name -eq $fontName } | Select-Object -First 1
    if (-not $ff) { $ff = $allFamilies[0] }
    $font = New-Object System.Drawing.Font($ff, [single]200, [System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $rect = New-Object System.Drawing.RectangleF(0, 0, [single]432, [single]432)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 120, 30, 20))
    $g2.DrawString($poem, $font, $brush, $rect, $sf)
    $font.Dispose()
    $bmp2.Save($fgPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g2.Dispose(); $bmp2.Dispose()
    "OK fg: $fgPath" | Out-File -FilePath $logPath -Append -Encoding utf8
    "DONE" | Out-File -FilePath $logPath -Append -Encoding utf8
} catch {
    "ERROR: $($_.Exception.Message)`n$($_.ScriptStackTrace)" | Out-File -FilePath $logPath -Append -Encoding utf8
}
