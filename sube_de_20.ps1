# sube_de_20.ps1 — sin LFS: parte en trozos de 95 MB lo que pase de 95 MB y sube de 20 en 20 (add + commit + push)
# Uso:  .\sube_de_20.ps1 "mensaje"     (en la raíz del repo)
param([string]$Mensaje = "Subida por tandas")
$ErrorActionPreference = "Stop"
$Tanda  = 20
$Limite = 95MB
$Rama   = (git rev-parse --abbrev-ref HEAD).Trim()

function Lista {
    # nuevos (sin los de .gitignore) y cambiados; quotepath=false para los nombres con tildes
    $n = git -c core.quotepath=false ls-files --others --exclude-standard
    $m = git -c core.quotepath=false ls-files --modified
    @($n) + @($m) | Where-Object { $_ } | Sort-Object -Unique
}

# 1. los grandes: fichero.ext -> fichero.ext.001, .002... y el original, a .gitignore
foreach ($f in Lista) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
    $tam = (Get-Item -LiteralPath $f).Length
    if ($tam -le $Limite) { continue }
    Write-Host "Parto $f ($([math]::Round($tam / 1MB)) MB)"
    $ent = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $f).Path)
    $buf = New-Object byte[] $Limite
    $i = 1
    while (($leidos = $ent.Read($buf, 0, $buf.Length)) -gt 0) {
        $trozo = "{0}.{1:D3}" -f $f, $i
        $sal = [System.IO.File]::Create((Join-Path (Get-Location) $trozo))
        $sal.Write($buf, 0, $leidos); $sal.Close()
        $i++
    }
    $ent.Close()
    $ign = if (Test-Path .gitignore) { Get-Content .gitignore } else { @() }
    if ($ign -notcontains $f) { Add-Content .gitignore $f }
}

# 2. la lista (ya sin los grandes)
$ficheros = @(Lista)
$total = $ficheros.Count
if ($total -eq 0) { Write-Host "No hay nada que subir."; exit 0 }
Write-Host "$total ficheros, en tandas de $Tanda, a la rama $Rama"

# 3. de 20 en 20
for ($i = 0; $i -lt $total; $i += $Tanda) {
    $trozo = $ficheros[$i..([math]::Min($i + $Tanda, $total) - 1)]
    $n = [math]::Floor($i / $Tanda) + 1
    git add -- $trozo
    if ($LASTEXITCODE -ne 0) { throw "git add falló en la tanda $n" }
    git commit -q -m "$Mensaje ($n`: ficheros $($i + 1)-$($i + $trozo.Count) de $total)"
    if ($LASTEXITCODE -ne 0) { throw "git commit falló en la tanda $n" }
    $ok = $false
    foreach ($t in 1..5) {
        git push -q origin $Rama
        if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        Write-Host "Push fallido, reintento en $($t * 2) s"; Start-Sleep -Seconds ($t * 2)
    }
    if (-not $ok) { throw "El push falla: paro en la tanda $n" }
    Write-Host "Tanda $n subida ($($trozo.Count) ficheros)"
}
Write-Host "Hecho: $total ficheros subidos."