[CmdletBinding()]
Param(
  [String] $SysInternalsFolder = '.'
  , [String[]] $ExtensionsToSelect = @('.exe', '.chm')
)

function Is-Elevated {
  $prp = new-object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
  $prp.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
 }
 
 function Run-ThisElevated {  #must be called from script body level
   if (!(Is-Elevated)) {
     $parent = (get-variable myinvocation -Scope 1).Value
     $parentfolder = Split-Path -Path $parent.MyCommand.Path -Parent
     Start-Process - -FilePath powershell.exe -Verb runAs -ArgumentList ('-NoExit -Command cd {0}; {1}' -f $parentfolder, $parent.Line)
     exit
   }
 }
 
Run-ThisElevated

$BaseURI =  'https://live.sysinternals.com'
$req = invoke-webrequest -URI $BaseURI # -UseBasicParsing

if ($req.StatusCode -eq 200) {
  $FilesOnPage = select-string -Pattern '(\d+/\d+/\d+ +\d+:\d+ \w+)\s+(\d+)\s+<A .*?HREF="(.+?)".*?>([\w\.]+)' -InputObject $req.content -AllMatches

  $FileList = @()
  foreach ($match in $FilesOnPage.Matches) {
  # $match = $FilesOnPage.matches[0]
    try {
      $Timestamp = [DateTime]::Parse($match.groups[1].value, [CultureInfo]::new('en-US')) 
      $LocalFileName = Join-Path -Path $SysInternalsFolder -ChildPath $match.groups[4].value
      if ($null -eq $ExtensionsToSelect -or $ExtensionsToSelect -contains [io.path]::GetExtension($LocalFileName)) {
        $FileObject = [PSCustomObject] @{
                        Timestamp = $Timestamp
                        Size = [int64]$match.groups[2].value
                        Name = $match.groups[4].value
                        Link = $match.groups[3].value
                        LocalSize = 0
                        LocalTimestamp = $null
                      }
        if (Test-Path $LocalFileName) {
          $LocalFile = Get-Item $LocalFileName
          $FileObject.LocalSize = $LocalFile.Length
          $FileObject.LocalTimestamp = $LocalFile.LastWriteTime
        }
        $FileList += $FileObject
      }
    }
    catch {
      Write-Host -Object ('Caught exception on [{0}]' -f $match.ToString())
    }
  }
  #$FileList | ? { $_.Timestamp -gt $_.LocalTimestamp -and $_.LocalSize -ne 0} | ft Name, Timestamp, LocalTimestamp, Size, LocalSize
  #$FileList | ? { $_.Size -ne $_.LocalSize -and $_.LocalSize -ne 0} | ft Name, Timestamp, LocalTimestamp, Size, LocalSize
  #$FileList | ? { $_.LocalSize -eq 0} | ft Name, Timestamp, Size
  $ChangedFileList = $FileList | 
    where-object { $_.Timestamp -gt $_.LocalTimestamp} 
  Write-Host -Object ('Files to be updated: {0}' -f $ChangedFileList.Count)
  $ChangedFileList | 
    foreach-object {
      $name = $_.Name
      Write-Host -Object  ('Processing file: {0}' -f $Name)
      $Process = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($name)) -ErrorAction SilentlyContinue
      if ($Process) {
        Stop-Process -Name $Process -Force
      }
      try {
        invoke-webrequest -URI ($baseURI + $_.Link) -OutFile (Join-Path -Path $SysInternalsFolder -ChildPath $Name) -ErrorAction SilentlyContinue
      }
      catch{
        Write-Error -Message ('Exception processing download: {0}' -f $Name)
      }
      if ($Process) {
        Start-Process -FilePath $Process.Path
      }
    }
} else {
  Write-Warning -Message ('Could not connect to {0}, http error {1}' -f $BaseURI, $req.StatusCode)
}
