<#
    Shared by GoDark.ps1 and GoOnline.ps1: saves Wi-Fi profiles (including passwords) to an
    encrypted file and restores them.

    The key is derived from a passphrase you type each time, so nothing on this machine can
    decrypt the file on its own. File format:
        "WFV1" | salt (16) | IV (16) | AES-256-CBC ciphertext | HMAC-SHA256 (32)
    Works in Windows PowerShell 5.1 and PowerShell 7.
#>

$VaultFile = Join-Path $PSScriptRoot 'wifi-profiles.enc'
$VaultMagic = [Text.Encoding]::ASCII.GetBytes('WFV1')
$VaultIterations = 310000

function Read-Passphrase([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-VaultKeys([string]$Passphrase, [byte[]]$Salt) {
    $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($Passphrase, $Salt, $VaultIterations,
        [Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $bytes = $kdf.GetBytes(64)
        @{ Enc = [byte[]]$bytes[0..31]; Mac = [byte[]]$bytes[32..63] }
    } finally { $kdf.Dispose() }
}

function Save-WifiVault([string]$Passphrase) {
    # Export to a private temp folder (netsh can only write clear-text XML), read, then delete.
    $tmp = Join-Path $env:TEMP ([Guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        netsh wlan export profile key=clear folder="$tmp" | Out-Null
        $profiles = @{}
        # ReadAllText, not Get-Content: Get-Content strings carry extra properties that PS 5.1's
        # ConvertTo-Json writes out as objects instead of plain strings.
        foreach ($f in Get-ChildItem $tmp -Filter *.xml) { $profiles[$f.Name] = [IO.File]::ReadAllText($f.FullName) }
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($profiles.Count -eq 0) { return 0 }

    $plain = [Text.Encoding]::UTF8.GetBytes(($profiles | ConvertTo-Json -Compress))
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object byte[] 16; $rng.GetBytes($salt)
    $keys = Get-VaultKeys $Passphrase $salt

    $aes = [Security.Cryptography.Aes]::Create()
    $aes.Key = $keys.Enc
    $aes.GenerateIV()
    $cipher = $aes.CreateEncryptor().TransformFinalBlock($plain, 0, $plain.Length)
    $body = [byte[]]($VaultMagic + $salt + $aes.IV + $cipher)
    $aes.Dispose()

    $hmac = [Security.Cryptography.HMACSHA256]::new($keys.Mac)
    $tag = $hmac.ComputeHash($body)
    $hmac.Dispose()

    [IO.File]::WriteAllBytes($VaultFile, [byte[]]($body + $tag))
    return $profiles.Count
}

# Returns a hashtable of file name -> profile XML, or $null if the passphrase is wrong.
function Open-WifiVault([string]$Passphrase) {
    $data = [IO.File]::ReadAllBytes($VaultFile)
    if ($data.Length -lt 4 + 16 + 16 + 16 + 32 -or
        [Text.Encoding]::ASCII.GetString($data, 0, 4) -ne 'WFV1') {
        throw "$VaultFile is not a Wi-Fi vault file."
    }
    $body = [byte[]]$data[0..($data.Length - 33)]
    $tag = [byte[]]$data[($data.Length - 32)..($data.Length - 1)]
    $salt = [byte[]]$data[4..19]
    $iv = [byte[]]$data[20..35]
    $cipher = [byte[]]$data[36..($body.Length - 1)]
    $keys = Get-VaultKeys $Passphrase $salt

    $hmac = [Security.Cryptography.HMACSHA256]::new($keys.Mac)
    $expected = $hmac.ComputeHash($body)
    $hmac.Dispose()
    $diff = 0
    for ($i = 0; $i -lt 32; $i++) { $diff = $diff -bor ($expected[$i] -bxor $tag[$i]) }
    if ($diff -ne 0) { return $null }

    $aes = [Security.Cryptography.Aes]::Create()
    $aes.Key = $keys.Enc
    $aes.IV = $iv
    $plain = $aes.CreateDecryptor().TransformFinalBlock($cipher, 0, $cipher.Length)
    $aes.Dispose()

    $profiles = @{}
    ([Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { $profiles[$_.Name] = $_.Value }
    return $profiles
}

# Returns the number of profiles that failed to restore.
function Restore-WifiProfiles([hashtable]$Profiles) {
    $failed = 0
    $tmp = Join-Path $env:TEMP ([Guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        foreach ($name in $Profiles.Keys) {
            $label = [IO.Path]::GetFileNameWithoutExtension($name)
            $path = Join-Path $tmp $name
            [IO.File]::WriteAllText($path, [string]$Profiles[$name])
            $out = netsh wlan add profile filename="$path" user=all
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[*] Restored Wi-Fi profile $label" -ForegroundColor Cyan
            } else {
                Write-Host "[!] Could not restore $label`: $out" -ForegroundColor Red
                $failed++
            }
        }
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $failed
}
