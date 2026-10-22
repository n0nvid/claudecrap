<#
    Shared by WiFi.ps1, Lab.ps1 and Evidence.ps1: shows a title and asks for one of a few words.
#>

# Shows the title and choices, then returns the word typed, or exits if it isn't one of them.
# Capitals are required on purpose: typing BACKUP / RESTORE / DARK takes a moment of thought.
function Read-MenuChoice([string]$Title, [string]$Status, [System.Collections.Specialized.OrderedDictionary]$Choices) {
    Write-Host ""
    Write-Host "  $Title  " -BackgroundColor DarkBlue -ForegroundColor White
    if ($Status) { Write-Host "  $Status" }
    Write-Host ""
    foreach ($word in $Choices.Keys) { Write-Host ("  {0,-8} {1}" -f $word, $Choices[$word]) }
    Write-Host ""
    $answer = (Read-Host "  Type $(@($Choices.Keys) -join ' or ') (in capitals)").Trim()
    if ($answer -cnotin @($Choices.Keys)) {
        if ($answer -in @($Choices.Keys)) {
            Write-Host "[!] Nothing done - type it in capitals ($($answer.ToUpper()))." -ForegroundColor Red
        } else {
            Write-Host "[!] Nothing done." -ForegroundColor Red
        }
        exit 1
    }
    return $answer
}
