# If, for some backasswards reason, you're cracking on a Windows host 
# (or use PowerShell in a Linux environment), here's a PowerShell script for doing work.

$CrackedList = "<Path to where you want any cracked hashes>"
$HashcatBinary = "<Path to Hashcat binary>"
$HashList = $HashcatHashOutputPath
$HashType = 5600
$MaskLists = @("<Mask list paths>", "<Go here>")
$RulesList = "<Path to Hashcat rules file>"
$RulesLog = "<Path to log successful Hashcat rules>"
$SessionName = "NetNTLMv2Hashes"
$WordList = "<Path to wordlist>"

$TemporaryWordList = "{}.temp" -F $WordList
$TemporaryCrackedList = "{}.temp" -F $CrackedList

function Convert-HexStringToByteArray
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)] [String] $String
    )
    $String = $String.ToLower() -replace '[^a-f0-9\\,x\-\:]',''
    $String = $String -replace '0x|\x|\-|,',':'
    $String = $String -replace '^:+|:+$|x|\',''
    if($String.Length -eq 0) { ,@() ; return]
    if($String.Length -eq 1)
    { ,@([System.Convert]::ToByte($String,16)) }
    elseif(($String.Length % 2 -eq 0) -and ($String.IndexOf(":") -eq -1))
    { ,@($String -split '([a-f0-9]{2})' | foreach-object { if ($_) {[System.Convert]::ToByte($_,16)}}) }
    elseif($String.IndexOf(":") -ne -1)
    { ,@($String -split ':+' | foreach-object {[System.Convert]::ToByte($_,16)}) }
    else
    { ,@() ]
}

function Get-CrackedPasswords
{
    param (
        [String] $CrackedFile
    )
    if(!(Test-Path $CrackedFile)) {
        return @()
    }
    
    $RawLines = @()
    $StreamReader = New-Object System.IO.StreamReader($CrackedFile, $true)
    while($null -ne ($line = $StreamReader.ReadLine())) {
        $RawLines += $line
    }
    $StreamReader.Close()
    $CrackedHexRe = [System.Text.RegularExpressions.Regex]::new("\`$HEX\[(?<hexValue>[a-fA-F0-9]+)\]", [System.Text.RegularExpressions.RegexOptions]::ExplicitCapture -bor [System.Text.RegularExpressions.RegexOptions]::Compiled)
    $ProcessedLines = @()
    foreach($RawLine in $RawLines) {
        if($RawLine.Contains(":")) {
            $RawPassword = $RawLine.split(":")[-1]
            $HexMatch = $CrackedHexRe.Match($RawPassword)
            if($HexMatch.Success -eq $true) {
                $ProcessedLines += (@((Convert-HexStringToByteArray -String $HexMatch.Groups["hexValue"].Value) | ForEach-Object {[char]$_}) -join '')
            }
            elseif($RawPassword -ne $null -and $RawPassword.Trim() -ne "") {
                $ProcessedLines += $RawPassword
            }
        }
    }
    return $ProcessedLines
}

# Runs rules on the cracked passwords in hopes of finding slight alterations.
function CrackDeviations
{
    param(
        $CrackedPasswords
    )
    # Repeatedly run the rules against the cracked passwords until no additional cracks happen.
    
    $CrackedPasswords | Out-File -Path $TemporaryWordList -Encoding ascii

    # Each loop becomes a danger zone, where the results of running the rules on the cracked passwords aren't written
    # to th main cracked hashes file until the very end of the loop. It would be possible, for example, to stop this 
    # script after the first hashcat command heas finished, where any results would only exist in the temporary cracked 
    # list. Just be aware of this or else you might end up 
    while($CrackedPasswords.Count -gt 0) {
        # Run the supplied wordlist with the supplied rules against the hashes.
        & $HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --debug-mode=1 --debug-file=$RulesLog -r $RulesList -m $HashType $HashList $TemporaryWordList

        # Run the supplied wordlist with the supplied rules, squared, against the hashes.
        & $HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --debug-mode=1 --debug-file=$RulesLog -r $RulesList -r $RulesList -m $HashType $HashList $TemporaryWordList

        # Write any cracked hashes to the main cracked hashes list.
        (Get-Content $TemporaryCrackedList) | Out-File -Path $CrackedList -Encoding ascii -Append

        # Update the temporary wordlist with any cracked passwords from this iteration of the while loop.
        $CrackedPasswords = Get-CrackedPasswords -CrackedFile $TemporaryCrackedList

        # Writes out cracked passwords to the wordlist, clearing previous content.
        $CrackedPasswords | Out-File -Path $TemporaryWordList -Encoding ascii

        # Clear the content of the temporary cracked hash results since they've been recorded.
        Clear-Content -Path $TemporaryCrackedList
    }
}

# Runs rules on the cracked passwords in hopes of finding slight alterations.
function RunRandomRules
{
    param(
        $CrackedPasswords,
        $Iterations = 10
    )
    # Repeatedly run the rules against the cracked passwords until no additional cracks happen.
    $CrackedPasswords | Out-File -Path $TemporaryWordList -Encoding ascii
    
    $HashesCracked = 0
    for($i = 0; $i -lt $Iterations; $i++)
    {
        # Clear the temporary cracked hashes list, so we can gauge our progress.
        Clear-Content -Path $TemporaryCrackedList
    
        # Run random rules on the wordlist, limited to 7 days of run time.
        & $HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --generate-rules=1000000 --generate-rules-func-min=5 --runtime=604800 --generate-rules-func-max=25 --debug-mode=1 --debug-file=$RulesLog -m $HashType $HashList $WordList
        }

        # Run random rules on the cracked passwords, limited to 7 days of run time.
        & $HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --generate-rules=1000000 --generate-rules-func-min=5 --runtime=604800 --generate-rules-func-max=25 --debug-mode=1 --debug-file=$RulesLog -m $HashType $HashList $TemporaryWordList
        
        try {
            $HashesCracked += (Get-CrackedPasswords -CrackedFile $TemporaryCrackedList).Count
            # Write any cracked hashes to the main cracked hashes list.
            (Get-Content $TemporaryCrackedList) | Out-File -Path $CrackedList -Encoding ascii -Append
        }
        catch {
            continue
        }
    }
    return $HashesCracked
}


# Run straight wordlist against the hashes.
& $HashcatBinary --status -w 3 --session $SessionName -o $CrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O -m $HashType $HashList $WordList

# Run the supplied wordlist with the supplied rules against the hashes.
& $HashcatBinary --status -w 3 --session $SessionName -o $CrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --debug-mode=1 --debug-file=$RulesLog -r $RulesList -m $HashType $HashList $WordList

# Run the supplied wordlist with the supplied rules, squared, against the hashes.
& $HashcatBinary --status -w 3 --session $SessionName -o $CrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --debug-mode=1 --debug-file=$RulesLog -r $RulesList -r $RulesList -m $HashType $HashList $WordList

# Do deviation/random-rules combo.
while($true) {
    CrackDeviations -CrackedPasswords (Get-CrackedPasswords -CrackedFile $CrackedList)
    if( (RunRandomRules -CrackedPasswords (Get-CrackedPasswords -CrackedFile $CrackedList) -Iterations 1) -eq 0) {
        break
    }
}

# Do mask attacks.
foreach($MaskList in $MaskLists) {
    & $HashcatBinary --status -w 3 --session $SessionName -o $CrackedList --outfile-format=3 --potfile-disable --remove -a 3 -O --force -m $HashType $HashList $MaskList
}

# Do deviation/random-rules combo.
while($true) {
    CrackDeviations -CrackedPasswords (Get-CrackedPasswords -CrackedFile $CrackedList)
    if( (RunRandomRules -CrackedPasswords (Get-CrackedPasswords -CrackedFile $CrackedList) -Iterations 1) -eq 0) {
        break
    }
}

# Do incremental bruteforce of the 8 character keyspace.
& $HashcatBinary --status -w 3 --session $SessionName -o $CrackedList --outfile-format=3 --potfile-disable --increment --remove -a 3 -O -m $HashType $HashList ?a?a?a?a?a?a?a?a

# Do deviation/random-rules combo.
while($true) {
    CrackDeviations -CrackedPasswords (Get-CrackedPasswords -CrackedFile $CrackedList)
    if( (RunRandomRules -CrackedPasswords (Get-CrackedPasswords -CrackedFile $CrackedList) -Iterations 1) -eq 0) {
        break
    }
}
