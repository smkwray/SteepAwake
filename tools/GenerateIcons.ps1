Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectRoot 'assets'
$iconSizes = @(16, 20, 24, 32, 48, 64)

$palettes = @{
    Dark = @{
        Normal = [Drawing.ColorTranslator]::FromHtml('#8A929B')
        Timed = [Drawing.ColorTranslator]::FromHtml('#FBBF24')
        Indefinite = [Drawing.ColorTranslator]::FromHtml('#34D399')
    }
    Light = @{
        Normal = [Drawing.ColorTranslator]::FromHtml('#6B7280')
        Timed = [Drawing.ColorTranslator]::FromHtml('#B45309')
        Indefinite = [Drawing.ColorTranslator]::FromHtml('#047857')
    }
}

function New-TeacupPng {
    param(
        [int]$Size,
        [ValidateSet('Normal', 'Timed', 'Indefinite')]
        [string]$Mode,
        [ValidateSet('Dark', 'Light')]
        [string]$Theme
    )

    $bitmap = [Drawing.Bitmap]::new(
        $Size, $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.Clear([Drawing.Color]::Transparent)

    $color = $palettes[$Theme][$Mode]
    $brush = [Drawing.SolidBrush]::new($color)
    $wall = [Math]::Max(1.25, $Size * 0.078)

    # Handle first, allowing the opaque bowl to hide its two joins.
    $handlePen = [Drawing.Pen]::new($color, $wall)
    $handlePen.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $handlePen.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $handleRect = [Drawing.RectangleF]::new(
        $Size * 0.500, $Size * 0.313,
        $Size * 0.438, $Size * 0.312)
    $graphics.DrawArc($handlePen, $handleRect, 270, 180)

    # One friendly, squat silhouette is shared by every state.
    $cup = [Drawing.Drawing2D.GraphicsPath]::new(
        [Drawing.Drawing2D.FillMode]::Alternate)
    $cup.StartFigure()
    $cup.AddLine($Size * 0.125, $Size * 0.125, $Size * 0.750, $Size * 0.125)
    $cup.AddLine($Size * 0.750, $Size * 0.125, $Size * 0.750, $Size * 0.203)
    $cup.AddLine($Size * 0.750, $Size * 0.203, $Size * 0.719, $Size * 0.203)
    $cup.AddBezier(
        $Size * 0.719, $Size * 0.203,
        $Size * 0.705, $Size * 0.470,
        $Size * 0.690, $Size * 0.680,
        $Size * 0.625, $Size * 0.735)
    $cup.AddBezier(
        $Size * 0.625, $Size * 0.735,
        $Size * 0.565, $Size * 0.775,
        $Size * 0.310, $Size * 0.775,
        $Size * 0.250, $Size * 0.735)
    $cup.AddBezier(
        $Size * 0.250, $Size * 0.735,
        $Size * 0.185, $Size * 0.680,
        $Size * 0.170, $Size * 0.470,
        $Size * 0.156, $Size * 0.203)
    $cup.AddLine($Size * 0.156, $Size * 0.203, $Size * 0.125, $Size * 0.203)
    $cup.CloseFigure()

    # Empty and timed cups contain a transparent air pocket. Its sides follow
    # the bowl taper so wall thickness remains optically even.
    if ($Mode -ne 'Indefinite') {
        $airBottom = if ($Mode -eq 'Timed') { 0.430 } else { 0.660 }
        $progress = ($airBottom - 0.203) / (0.660 - 0.203)
        $innerLeft = 0.234 + (0.305 - 0.234) * $progress
        $innerRight = 0.641 + (0.570 - 0.641) * $progress

        $cup.StartFigure()
        $cup.AddLine($Size * 0.234, $Size * 0.203, $Size * 0.641, $Size * 0.203)
        $cup.AddLine($Size * 0.641, $Size * 0.203, $Size * $innerRight, $Size * $airBottom)
        if ($Mode -eq 'Normal') {
            $cup.AddBezier(
                $Size * $innerRight, $Size * $airBottom,
                $Size * 0.535, $Size * 0.700,
                $Size * 0.340, $Size * 0.700,
                $Size * $innerLeft, $Size * $airBottom)
        } else {
            $cup.AddLine(
                $Size * $innerRight, $Size * $airBottom,
                $Size * $innerLeft, $Size * $airBottom)
        }
        $cup.AddLine(
            $Size * $innerLeft, $Size * $airBottom,
            $Size * 0.234, $Size * 0.203)
        $cup.CloseFigure()
    }
    $graphics.FillPath($brush, $cup)

    # A detached rounded saucer makes the mark read as a teacup at 16 px.
    $saucerHeight = [Math]::Max(1.0, $Size * 0.062)
    $saucerPen = [Drawing.Pen]::new($color, $saucerHeight)
    $saucerPen.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $saucerPen.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawLine(
        $saucerPen,
        $Size * 0.062, $Size * 0.844,
        $Size * 0.813, $Size * 0.844)

    foreach ($resource in @(
        $saucerPen, $cup, $handlePen, $brush, $graphics)) {
        $resource.Dispose()
    }

    $stream = [IO.MemoryStream]::new()
    $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $bytes = $stream.ToArray()
    $stream.Dispose()
    return ,$bytes
}

function Write-MultiSizeIcon {
    param(
        [string]$Path,
        [ValidateSet('Normal', 'Timed', 'Indefinite')]
        [string]$Mode,
        [ValidateSet('Dark', 'Light')]
        [string]$Theme
    )

    $images = foreach ($size in $iconSizes) {
        [pscustomobject]@{
            Size = $size
            Data = [byte[]](New-TeacupPng -Size $size -Mode $Mode -Theme $Theme)
        }
    }

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create)
    $writer = [IO.BinaryWriter]::new($stream)
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$images.Count)
    $offset = 6 + (16 * $images.Count)

    foreach ($image in $images) {
        $writer.Write([byte]$image.Size)
        $writer.Write([byte]$image.Size)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$image.Data.Length)
        $writer.Write([uint32]$offset)
        $offset += $image.Data.Length
    }
    foreach ($image in $images) {
        $writer.Write($image.Data)
    }

    $writer.Dispose()
    $stream.Dispose()
}

foreach ($theme in @('Dark', 'Light')) {
    foreach ($mode in @('Normal', 'Timed', 'Indefinite')) {
        $name = $mode.ToLowerInvariant() + '-' + $theme.ToLowerInvariant() + '.ico'
        Write-MultiSizeIcon `
            -Path (Join-Path $outputDirectory $name) `
            -Mode $mode `
            -Theme $theme
    }
}

[IO.File]::WriteAllBytes(
    (Join-Path $outputDirectory 'brand-dark.png'),
    [byte[]](New-TeacupPng -Size 256 -Mode Indefinite -Theme Dark))
[IO.File]::WriteAllBytes(
    (Join-Path $outputDirectory 'brand-light.png'),
    [byte[]](New-TeacupPng -Size 256 -Mode Indefinite -Theme Light))
