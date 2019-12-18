# If, for some backasswards reason, you're cracking on a Windows host 
# (or use PowerShell in a Linux environment), here's a PowerShell script for doing work.

$CrackedList = "<Path to where you want any cracked hashes>"
$HashcatBinary = "<Name of Hashcat exe>"
$HashcatBinaryDirectory = "<Name of directory Hashcat exe is in>" 
$HashList = "<Path to appropriately formatted hashes>"
$HashType = 1000
$MaskLists = @("<Mask list paths>", "<Go here>")
$PrinceProcessorBinary = "<Path to the PrinceProcessor binary>"
$PrinceProcessorOutputFile = "<Path where PrinceProcessor should take a dump>"
$RulesList = "<Path to Hashcat rules file>"
$RulesLog = "<Path to log successful Hashcat rules>"
$SessionName = "ntHashes"
$WordList = "<Path to wordlist>"

$TemporaryWordList = "{0}.temp" -F $WordList
$TemporaryCrackedList = "{0}.temp" -F $CrackedList

function ClearContent
{
    param(
        $Path
    )
    if(Test-Path $Path) {
        Clear-Content -Path $Path -Force
    }
    else {
        New-Item -ItemType file $Path
    }
}

function Convert-HexStringToByteArray
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$True, ValueFromPipeline=$True)] [String] $String
    )
    $String = $String.ToLower() -replace '[^a-f0-9\\,x\-\:]',"
    $String = $String -replace '0x|\x|\-|,',':'
    $String = $String -replace '^:+|:+$|x|\',"
    if($String.Length -eq 0) { ,@() ; return }
    if($String.Length -eq 1)
    { ,@([System.Convert]::ToByte($String,16)) }
    elseif(($String.Length % 2 -eq 0) -and ($String.IndexOf(":") -eq -1))
    { ,@($String -split '([a-f0-9]{2})' | foreach-object { if ($_) {[System.Convert]::ToByte($_,16)}}) }
    elseif($String.IndexOf(":") -ne -1)
    { ,@($String -split ':+' | foreach-object {[System.Convert]::ToByte($_,16)}) }
    else
    { ,@() }
}

function Get-CrackedPasswords
{
    param (
        [String] $CrackedFile = "",
        $RawLines = @()
    )
    if($RawLines.Count -eq 0)
    {
        if(!(Test-Path $CrackedFile)) {
            return @()
        }
        $StreamReader = New-Object System.IO.StreamReader($CrackedFile, $true)
        while($null -ne ($line = $StreamReader.ReadLine())) {
            $RawLines += $line
        }
        $StreamReader.Close()
    }
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
function RunRuleAttacks
{
    param(
        $Words = @()
    )
    $CrackedPasswords = @()
    
    # If no words supplied, return an empty array.
    if($Words.Count -eq 0) {
        return $CrackedPasswords
    }
    
    # Repeatedly run the rules against the cracked passwords until no additional cracks happen.
    $Words | Out-File -FilePath $TemporaryWordList -Encoding ascii
    
    # Each loop becomes a danger zone, where the results of running the rules on the cracked passwords aren't written
    # to th main cracked hashes file until the very end of the loop. It would be possible, for example, to stop this 
    # script after the first hashcat command heas finished, where any results would only exist in the temporary cracked 
    # list. Just be aware of this or else you might end up overwriting some good cracks.
    
    # Clear out the the temporary cracked hashes file.
    ClearContent -Path $TemporaryCrackedList
    
    # Create an array to hold any newly cracked plaintext passwords, post running the rules.
    $TemporaryCrackedContent = @()
    
    # Declare a variable to establish the first iteration through the while loop.
    $FirstRun = $true
    
    # While this is either the first time through the loop or there are new plaintext values to run the rules on:
    while($FirstRun -eq $true -or $TemporaryCrackedContent.Count -gt 0) {
        $FirstRun = $false
    
        # Run the cracked passwords with the supplied rules against the hashes.
        Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --debug-mode=1 --debug-file=$RulesLog -r $RulesList -m $HashType $HashList $TemporaryWordList" | Out-Host

        # Run the cracked passwords with the supplied rules, squared, against the hashes.
        Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --debug-mode=1 --debug-file=$RulesLog -r $RulesList -r $RulesList -m $HashType $HashList $TemporaryWordList" | Out-Host

        # Write any cracked hashes to the main cracked hashes list.
        (Get-Content $TemporaryCrackedList) | Out-File -FilePath $CrackedList -Encoding ascii -Append

        # Get a list of the cracked passwords from the previous hashcat run.
        $TemporaryCrackedContent = Get-CrackedPasswords -CrackedFile $TemporaryCrackedList

        # Append all plaintext values cracked in this function, to show progress, etc.
        $CrackedPasswords += $TemporaryCrackedContent

        # Writes out cracked passwords to the wordlist, clearing previous content.
        $TemporaryCrackedContent | Out-File -FilePath $TemporaryWordList -Encoding ascii

        # Clear the content of the temporary cracked hash results since they've been recorded.
        ClearContent -Path $TemporaryCrackedList
    }
    return $CrackedPasswords
}

# Runs brutal masks against the hashes.
function RunMaskAttacks
{
    param(
        $Masks = @()
    )
    $CrackedPasswords = @()
    if($Masks.Count -eq 0) {
        return $CrackedPasswords
    }
    ClearContent -Path $TemporaryCrackedList
    foreach($MaskList in $MaskLists) {
        Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 3 -O --force -m $HashType $HashList $MaskList" | Out-Host
        
        # Write any cracked hashes to the main cracked hashes list.
        (Get-Content $TemporaryCrackedList) | Out-File -FilePath $CrackedList -Encoding ascii -Append
        
        # Get a list of the cracked passwords from the previous hashcat run.
        $CrackedPasswords += Get-CrackedPasswords -CrackedFile $TemporaryCrackedList
        
        # Clear the temporary cracked hashes file.
        ClearContent -Path $TemporaryCrackedList
    }
    return $CrackedPasswords
}

# Runs a bruteforce attack.
function RunBruteForceAttack
{
    param(
        [String] $Mask = "?a?a?a?a?a?a?a?a",
        [switch] $Increment = $false
    )
    $CrackedPasswords = @()
    if($Masks.Count -eq 0) {
        return $CrackedPasswords
    }
    ClearContent -Path $TemporaryCrackedList
    if($Increment -eq $true) {    
        Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $CrackedList --outfile-format=3 --potfile-disable --increment --remove -a 3 -O -m $HashType $HashList $Mask" | Out-Host
    }
    else {
        Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $CrackedList --outfile-format=3 --potfile-disable --remove -a 3 -O -m $HashType $HashList $Mask" | Out-Host
    }
    # Write any cracked hashes to the main cracked hashes list.
    (Get-Content $TemporaryCrackedList) | Out-File -FilePath $CrackedList -Encoding ascii -Append

    # Get a list of the cracked passwords from the previous hashcat run.
    $CrackedPasswords = Get-CrackedPasswords -CrackedFile $TemporaryCrackedList

    # Clear the temporary cracked hashes file.
    ClearContent -Path $TemporaryCrackedList

    return $CrackedPasswords
}

# Runs a prepend/append attack.
function RunPrependAppendAttack
{
    param(
        [String] $Mask = "?a?a?a?a?a",
        [switch] $Increment = $false,
        $WordListPaths = @()
    )
    $CrackedPasswords = @()
    if($WordListPaths.Count -eq 0) {
        return $CrackedPasswords
    }
    ClearContent -Path $TemporaryCrackedList
    foreach($WordListPath in $WordListPaths) {
        if($Increment -eq $true) {
            Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --increment --remove -a 6 -O -m $HashType $HashList $WordListPath $Mask" | Out-Host
            Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --increment --remove -a 7 -O -m $HashType $HashList $Mask $WordListPath" | Out-Host
        }
        else {
            Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 6 -O -m $HashType $HashList $WordListPath $Mask" | Out-Host
            Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 7 -O -m $HashType $HashList $Mask $WordListPath" | Out-Host
        }
        
        # Write any cracked hashes to the main cracked hashes list.
        (Get-Content $TemporaryCrackedList) | Out-File -FilePath $CrackedList -Encoding ascii -Append
        
        # Get a list of the cracked passwords from the previous hashcat run.
        $CrackedPasswords += Get-CrackedPasswords -CrackedFile $TemporaryCrackedList
        
        # Clear the temporary cracked hashes file.
        ClearContent -Path $TemporaryCrackedList
    }
    return $CrackedPasswords
}

# Runs rules on the cracked passwords in hopes of finding slight alterations.
function RunRandomRules
{
    param(
        $CrackedPasswords,
        $Iterations = 10
    )
    # Repeatedly run the rules against the cracked passwords until no additional cracks happen.
    $CrackedPasswords | Out-File -FilePath $TemporaryWordList -Encoding ascii
    
    $HashesCracked = 0
    for($i = 0; $i -lt $Iterations; $i++)
    {
        # Clear the temporary cracked hashes list, so we can gauge our progress.
        ClearContent -Path $TemporaryCrackedList
    
        # Run random rules on the wordlist, limited to 7 days of run time.
        Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --generate-rules=1000000 --generate-rules-func-min=5 --runtime=604800 --generate-rules-func-max=25 --debug-mode=1 --debug-file=$RulesLog -m $HashType $HashList $WordList" | Out-Host

        # Run random rules on the cracked passwords, limited to 7 days of run time.
        Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --generate-rules=1000000 --generate-rules-func-min=5 --runtime=604800 --generate-rules-func-max=25 --debug-mode=1 --debug-file=$RulesLog -m $HashType $HashList $TemporaryWordList" | Out-Host
        
        try {
            $HashesCracked += (Get-CrackedPasswords -CrackedFile $TemporaryCrackedList).Count
            # Write any cracked hashes to the main cracked hashes list.
            (Get-Content $TemporaryCrackedList) | Out-File -FilePath $CrackedList -Encoding ascii -Append
        }
        catch {
            continue
        }
    }
    return $HashesCracked
}

# Runs the princeprocessor on the supplied wordlist and then attempts to fill the harddrive.
function RunPrinceProcessorAttack
{
    param(
        [String] $WordListPath = ""    
    )
    $CrackedPasswords = @()
    if(!Test-Path $WordListPath) {
        return $CrackedPasswords
    }
    ClearContent -Path $TemporaryCrackedList
    Invoke-Expression "$PrinceProcessorBinary --pw-max=16 --pw-min=8 --output-file=$PrinceProcessorOutputFile $WordListPath" | Out-Host

    # Run straight wordlist against the hashes.
    Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O -m $HashType $HashList $PrinceProcessorOutputFile" | Out-Host

    # Write any cracked hashes to the main cracked hashes list.
    (Get-Content $TemporaryCrackedList) | Out-File -FilePath $CrackedList -Encoding ascii -Append

    # Get a list of the cracked passwords from the previous hashcat run.
    $CrackedPasswords += Get-CrackedPasswords -CrackedFile $TemporaryCrackedList
        
    # Clear the temporary cracked hashes file.
    ClearContent -Path $TemporaryCrackedList

    # Run the supplied wordlist with the supplied rules against the hashes.
    Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $TemporaryCrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --debug-mode=1 --debug-file=$RulesLog -r $RulesList -m $HashType $HashList $PrinceProcessorOutputFile" | Out-Host

    # Write any cracked hashes to the main cracked hashes list.
    (Get-Content $TemporaryCrackedList) | Out-File -FilePath $CrackedList -Encoding ascii -Append
        
    # Get a list of the cracked passwords from the previous hashcat run.
    $CrackedPasswords += Get-CrackedPasswords -CrackedFile $TemporaryCrackedList
        
    # Clear the temporary cracked hashes file.
    ClearContent -Path $TemporaryCrackedList
    
    # Remove the probably gigantic pp file from disk.
    Remove-Item -Path $PrinceProcessorOutputFile -Force
    
    return $CrackedPasswords
}

cd $HashcatBinaryDirectory

# Run straight wordlist against the hashes.
Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $CrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O -m $HashType $HashList $WordList" | Out-Host

# Run the supplied wordlist with the supplied rules against the hashes.
Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $CrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --debug-mode=1 --debug-file=$RulesLog -r $RulesList -m $HashType $HashList $WordList" | Out-Host

# Do basic rule deviation on all cracked passwords.
$CrackedPasswords = RunRuleAttacks -Words (Get-CrackedPasswords -CrackedFile $CrackedList)

# Do append/prepend attack on word list and cracked passwords.
(Get-CrackedPasswords -CrackedFile $CrackedList) | Out-File -FilePath $TemporaryWordList -Encoding ascii
$CrackedPasswords = RunPrependAppendAttack -Mask "?a?a?a?a?a" -Increment -WordListPaths @($WordList, $TemporaryWordList)

# Do basic rule deviation on all cracked passwords from the previous append/prepend attacks.
$CrackedPasswords = RunRuleAttacks -Words $CrackedPasswords

# Do incremental bruteforce of the 8 character keyspace.
$CrackedPasswords = RunBruteForceAttack -Mask "?a?a?a?a?a?a?a?a" -Increment

# Do basic rule deviation on all cracked passwords from the previous bruteforce attack.
$CrackedPasswords = RunRuleAttacks -Words $CrackedPasswords

# Run the supplied wordlist with the supplied rules, squared, against the hashes.
Invoke-Expression "./$HashcatBinary --status -w 3 --session $SessionName -o $CrackedList --outfile-format=3 --potfile-disable --remove -a 0 -O --debug-mode=1 --debug-file=$RulesLog -r $RulesList -r $RulesList -m $HashType $HashList $WordList" | Out-Host

# Do mask attacks.
$CrackedPasswords = RunMaskAttacks -Masks $MaskLists

# Do basic rule deviation on all cracked passwords from the previous mask attacks.
$CrackedPasswords = RunRuleAttacks -Words $CrackedPasswords

# Run the PrinceProcessor on the cracked passwords, and then run basic and rules-based attacks.
(Get-CrackedPasswords -CrackedFile $CrackedList) | Out-File -FilePath $TemporaryWordList -Encoding ascii
RunPrinceProcessorAttack -WordListPath $TemporaryWordList
