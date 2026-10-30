from pathlib import Path
import io,zipfile,base64,hashlib,json,argparse
parser=argparse.ArgumentParser(description='Build the self-contained installer from a prepared Supraworld Win64 folder.')
parser.add_argument('--win64',type=Path,default=Path(r'C:\Program Files (x86)\Steam\steamapps\common\Supraworld\Supraworld\Binaries\Win64'))
parser.add_argument('--output',type=Path,default=Path('outputs/Install-SupraTools.ps1'))
args=parser.parse_args()
root=args.win64
files={}
for name in ('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/UE4SS-settings.ini','ue4ss/LICENSE'):
    files[name]=(root/name).read_bytes()
for directory in ('UE4SS_SDK_Backends','Mods/shared','Mods/SupraTools','Mods/CheatManagerEnablerMod','Mods/ConsoleCommandsMod','Mods/ConsoleEnablerMod','Mods/Keybinds'):
    for p in (root/'ue4ss'/directory).rglob('*'):
        if p.is_file() and p.suffix.lower() not in ('.bak','.log','.dmp') and p.name not in ('SupraAssist.lua','SearchInspect.lua'):
            files[p.relative_to(root).as_posix()]=p.read_bytes()
assert 'ue4ss/Mods/SupraTools/Scripts/SearchWorldBeacons.lua' in files
files['payload-manifest.json']=json.dumps({k:hashlib.sha256(v).hexdigest() for k,v in files.items()},indent=2).encode()
stream=io.BytesIO()
with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
    for name,data in files.items():archive.writestr(name,data)
payload=stream.getvalue()
template=r'''# SupraTools unified installer. Includes UE4SS and SupraTools (original by Joric).
# Close the game first. Run: powershell -ExecutionPolicy Bypass -File .\Install-SupraTools.ps1
[CmdletBinding()]
param([string]$GamePath,[switch]$VerifyOnly)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
function HashBytes([byte[]]$bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally {$sha.Dispose()}
}
function SafePath([string]$base,[string]$relative) {
    $base=[IO.Path]::GetFullPath($base).TrimEnd('\','/')
    $path=[IO.Path]::GetFullPath((Join-Path $base $relative))
    if (-not $path.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw 'Unsafe payload path'}
    return $path
}
$payload=@'
@@PAYLOAD@@
'@
$bytes=[Convert]::FromBase64String($payload)
if ((HashBytes $bytes) -ne '@@ZIPHASH@@') {throw 'Embedded package is damaged.'}
$stream=[IO.MemoryStream]::new($bytes,$false)
$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read)
$package=@{}
try {
    foreach($entry in $zip.Entries) {
        $inputStream=$entry.Open();$buffer=[IO.MemoryStream]::new()
        try {$inputStream.CopyTo($buffer);$package[$entry.FullName]=$buffer.ToArray()} finally {$inputStream.Dispose();$buffer.Dispose()}
    }
} finally {$zip.Dispose();$stream.Dispose()}
$expected=[Text.Encoding]::UTF8.GetString($package['payload-manifest.json']) | ConvertFrom-Json
foreach($property in $expected.PSObject.Properties) {
    if ((HashBytes $package[$property.Name]) -ne $property.Value) {throw ('Payload hash mismatch: '+$property.Name)}
}
$package.Remove('payload-manifest.json')
if ($VerifyOnly -and -not $GamePath) {Write-Output ('Verified embedded package: '+$package.Count+' files.');return}
if (-not $GamePath) {
    $steamRoots=@('C:\Program Files (x86)\Steam')
    try {$steamRoots+= (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamPath} catch {}
    try {$steamRoots+= (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam').InstallPath} catch {}
    $libraries=@($steamRoots)
    foreach($steam in $steamRoots) {
        if (-not $steam) {continue}
        $vdf=Join-Path $steam 'steamapps\libraryfolders.vdf'
        if(Test-Path -LiteralPath $vdf) {
            $content=[IO.File]::ReadAllText($vdf)
            foreach($match in [regex]::Matches($content,'"path"\s*"([^"]+)"')) {$libraries+=$match.Groups[1].Value.Replace('\\','\')}
        }
    }
    foreach($library in ($libraries | Select-Object -Unique)) {
        if (-not $library) {continue}
        $candidate=Join-Path $library 'steamapps\common\Supraworld'
        if(Test-Path -LiteralPath (Join-Path $candidate 'Supraworld\Binaries\Win64\Supraworld-Win64-Shipping.exe')) {$GamePath=$candidate;break}
    }
}
if (-not $GamePath) {throw 'Supraworld not found. Specify -GamePath "D:\SteamLibrary\steamapps\common\Supraworld".'}
$GamePath=[IO.Path]::GetFullPath($GamePath)
if(Test-Path -LiteralPath (Join-Path $GamePath 'Supraworld-Win64-Shipping.exe')) {$target=$GamePath}
else {$target=Join-Path $GamePath 'Supraworld\Binaries\Win64'}
if(-not (Test-Path -LiteralPath (Join-Path $target 'Supraworld-Win64-Shipping.exe'))) {throw 'Selected directory does not contain Supraworld.'}
$writes=@{}
foreach($name in $package.Keys) {
    $destination=SafePath $target $name
    $isTool=$name.StartsWith('ue4ss/Mods/SupraTools/')
    if(Test-Path -LiteralPath $destination) {
        if ($name -eq 'dwmapi.dll' -and (HashBytes ([IO.File]::ReadAllBytes($destination))) -ne (HashBytes $package[$name])) {throw 'Another dwmapi.dll loader is installed. No files changed.'}
        if(-not $isTool) {continue}
    }
    $writes[$name]=$package[$name]
}
$modsPath=SafePath $target 'ue4ss/Mods/mods.txt'
$mods=if(Test-Path -LiteralPath $modsPath){[IO.File]::ReadAllText($modsPath)}else{''}
foreach($mod in @('CheatManagerEnablerMod','ConsoleCommandsMod','ConsoleEnablerMod','SupraTools','Keybinds')) {
    $pattern='(?m)^\s*'+[regex]::Escape($mod)+'\s*:\s*[01][^\r\n]*'
    $enabled=if($mod -in @('CheatManagerEnablerMod','ConsoleEnablerMod')){'0'}else{'1'}
    if([regex]::IsMatch($mods,$pattern)) {$mods=[regex]::Replace($mods,$pattern,$mod+' : '+$enabled)}
    else {$mods=$mods.TrimEnd()+"`r`n"+$mod+' : '+$enabled+"`r`n"}
}
$writes['ue4ss/Mods/mods.txt']=[Text.UTF8Encoding]::new($false).GetBytes($mods)
if($VerifyOnly) {Write-Output ('Verified package and target: '+$target+'. Planned writes: '+$writes.Count);return}
if(Get-Process -Name 'Supraworld-Win64-Shipping','Supraworld' -ErrorAction SilentlyContinue) {throw 'Close Supraworld before installation. No files changed.'}
$backup=Join-Path $target ('SupraTools-backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($backup) | Out-Null
$records=@()
# Finish and verify every backup before modifying the installation.
foreach($name in $writes.Keys) {
    $destination=SafePath $target $name
    $oldExists=Test-Path -LiteralPath $destination
    $oldHash=$null
    if($oldExists) {
        $saved=SafePath $backup ('files/'+$name)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($saved)) | Out-Null
        $old=[IO.File]::ReadAllBytes($destination);$oldHash=HashBytes $old
        [IO.File]::WriteAllBytes($saved,$old)
        if((HashBytes ([IO.File]::ReadAllBytes($saved))) -ne $oldHash) {throw 'Backup verification failed. No game files changed.'}
    }
    $records+= [pscustomobject]@{Name=$name;Existed=$oldExists;OriginalHash=$oldHash;InstalledHash=(HashBytes $writes[$name])}
}
@{Target=$target;Files=$records} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'manifest.json') -Encoding UTF8
$restore=@'
$ErrorActionPreference='Stop'
if(Get-Process -Name 'Supraworld-Win64-Shipping','Supraworld' -ErrorAction SilentlyContinue){throw 'Close Supraworld first.'}
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
function HashFile($path){$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Safe($base,$relative){$base=[IO.Path]::GetFullPath($base).TrimEnd('\','/');$path=[IO.Path]::GetFullPath((Join-Path $base $relative));if(-not $path.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe restore path'};return $path}
foreach($file in $manifest.Files){$dst=Safe $manifest.Target $file.Name;if(Test-Path -LiteralPath $dst){$hash=HashFile $dst;if($hash -ne $file.InstalledHash -and $hash -ne $file.OriginalHash){throw ('File changed after installation: '+$file.Name)}};if($file.Existed){$src=Safe $PSScriptRoot ('files/'+$file.Name);if((HashFile $src) -ne $file.OriginalHash){throw 'Backup hash mismatch'}}}
foreach($file in $manifest.Files){$dst=Safe $manifest.Target $file.Name;if($file.Existed){[IO.File]::WriteAllBytes($dst,[IO.File]::ReadAllBytes((Safe $PSScriptRoot ('files/'+$file.Name))))}elseif(Test-Path -LiteralPath $dst){Remove-Item -LiteralPath $dst};if($file.Existed -and (HashFile $dst) -ne $file.OriginalHash){throw 'Restoration verification failed'}}
Write-Output 'Previous files restored.'
'@
[IO.File]::WriteAllText((Join-Path $backup 'Restore.ps1'),$restore,[Text.UTF8Encoding]::new($true))
$modified=@()
try {
    foreach($record in $records) {
        $destination=SafePath $target $record.Name
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
        $modified+=$record
        [IO.File]::WriteAllBytes($destination,$writes[$record.Name])
        if((HashBytes ([IO.File]::ReadAllBytes($destination))) -ne $record.InstalledHash) {throw ('Installation verification failed: '+$record.Name)}
    }
} catch {
    $failure=$_
    foreach($record in $modified) {
        $destination=SafePath $target $record.Name
        if($record.Existed){[IO.File]::WriteAllBytes($destination,[IO.File]::ReadAllBytes((SafePath $backup ('files/'+$record.Name))))}
        elseif(Test-Path -LiteralPath $destination){Remove-Item -LiteralPath $destination}
    }
    throw $failure
}
Write-Output ('SupraTools installed and verified: '+$target)
Write-Output ('Backup and rollback script: '+$backup)
Write-Output 'Alt+H menu; Alt+Left tabs; Alt+B 3D beacons; Alt+K protection. The game was not launched.'
'''
encoded=base64.b64encode(payload).decode()
script=template.replace('@@PAYLOAD@@','\n'.join(encoded[i:i+120] for i in range(0,len(encoded),120))).replace('@@ZIPHASH@@',hashlib.sha256(payload).hexdigest())
out=args.output;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(script,encoding='utf-8-sig')
print(f'Created {out}: {len(files)-1} embedded files, {out.stat().st_size/1024/1024:.1f} MB')
