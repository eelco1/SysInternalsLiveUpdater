[CmdletBinding()]
Param(
  [String] $SysInternalsFolder = '.'
  , [String[]] $ExtensionsToSelect = @('.exe', '.chm')
)

$baseURI =  'https://live.sysinternals.com'
$req = invoke-webrequest -URI $baseURI # -UseBasicParsing

if ($req.StatusCode -eq 200) {
  $FilesOnPage = select-string -Pattern '(\d+/\d+/\d+ \d+:\d+ \w+)\s+(\d+)\s+<A .*?HREF="(.+?)".*?>([\w\.]+)' -InputObject $req.content -AllMatches

  $FileList = @()
  foreach ($match in $FilesOnPage.Matches) {
  # $match = $FilesOnPage.matches[0]
    try {
      $Timestamp = [DateTime]::ParseExact($match.groups[1].value, 'M/d/yyyy h:mm tt', [CultureInfo]::InvariantCulture) 
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
      Write-Host ('Caught exception on [{0}]' -f $match.ToString())
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
      try {
        $name = $_.Name
        Write-Host -Object  ('Processing download: {0}' -f $Name)
        invoke-webrequest -URI ($baseURI + $_.Link) -OutFile (Join-Path -Path $SysInternalsFolder -ChildPath $Name)
      }
      catch{
        Write-Error -Message ('Exception processing download: {0}' -f $Name)
      }
    }
}
