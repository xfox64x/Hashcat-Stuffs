# Random words and their popularity with Bing

#region == CHANGE ME! ==
# Output file for farmed words.
$OutputFilePath = "C:\RandomWordList.txt"

# Minimum word length to farm.
$MinimumWordLength = 6

# Total number of words to farm.
$TotalNumberOfWords = 5
#endregion

# Arrays with common vowels, consonants and endings.
[array] $Vowels = "a;a;a;a;e;e;e;e;i;i;i;o;o;o;u;u;y" -split ";"
[array] $Consonants = "b;b;br;c;c;c;ch;cr;d;f;g;h;j;k;l;m;m;m;n;n;p;p;ph;qu;r;r;r;s;s;s;sh;t;tr;v;w;x;z" -split ";"
[array] $Endings = "r;r;s;r;l;n;n;n;c;c;t;p" -split ";"

# Functions for random vowels, consonants, endings and words.
function Get-RandomVowel 
{ return $Vowels[(Get-Random($Vowels.Length))] }

function Get-RandomConsonant
{ return $Consonants[(Get-Random($Consonants.Length))] }

function Get-RandomEnding
{ return $Endings[(Get-Random($Endings.Length))] }

function Get-RandomSyllable ([int32] $PercentConsonants, [int32] $PercentEndings)
{  
   [string] $Syllable = ""
   if ((Get-Random(100)) -le $PercentConsonants) 
   { $Syllable+= Get-RandomConsonant }
   $Syllable+= Get-RandomVowel
   if ((Get-Random(100)) -le $PercentEndings) 
   { $Syllable+= Get-RandomEnding }
   return $Syllable
}

function Get-RandomWord ([int32] $MinSyllables, [int32] $MaxSyllables)
{  
   [string] $Word = ""
   [int32] $Syllables = ($MinSyllables) + (Get-Random(($MaxSyllables - $MinSyllables + 1)))
   for ([int32] $Count=1; $Count -le $Syllables; $Count++) 
   { $Word += Get-RandomSyllable 70 20 } <# Consonant 70% of the time, Ending 20% #>
   return $Word
}

# Regex to pull Bing results count from page source.
$resultsCountRegex = [System.Text.RegularExpressions.Regex]::new("\<span class=`"sb_count`".*?\>(?<ResultsCount>[0-9,]+) results\</span\>", [System.Text.RegularExpressions.RegexOptions]::ExplicitCapture -bor [System.Text.RegularExpressions.RegexOptions]::Compiled)

# Function to see how many pages Bing finds for a given term.
Function Get-BingCount([string] $Term) {

    # Start a timer to wait for a period that won't violate Microsoft's terms.
    $stopwatch = [system.diagnostics.stopwatch]::StartNew()

    # Navigate to the Bing page to query the $term
    $ie.Navigate("http://bing.com/search?q=%2B"+$term);

    # Wait for the page to load
    $timeout = 0
    while ($ie.Busy) {
        Start-Sleep -Milliseconds 100
        $timeout++
        If ($timeout -gt 100) {
            return 0
        }
    }    

    # Wait for a period that won't violate Microsoft's terms.
    $stopwatch.Stop()
    if($stopwatch.ElapsedMilliseconds -lt 1000)
    {
        Start-Sleep -Milliseconds (1000 - $stopwatch.ElapsedMilliseconds)
    }

    $MatchObject = $resultsCountRegex.Match($ie.Document.body.innerHTML)

    if($MatchObject.Success)
    {
        return [int]$MatchObject.Groups["ResultsCount"].Value
    }
    else
    {
        return 0
    }
}

Function DiscoverPopularWords
{
    param(
        $NumberOfWords = 10,
        $MinSyllables = 2,
        $MaxSyllables = 10,
        $MinWordLength = 6,
        $MinPopularity = 1000
    )

    # Create Internet Explorer object
    $ie = New-Object -ComObject "InternetExplorer.Application"     

    $PopularWords = @{}
    $LastProgressLine = ""
    while($PopularWords.Count -lt $NumberOfWords)
    {
        # Get a random word
        $word = Get-RandomWord $MinSyllables $MaxSyllables
        
        while($word.Length -lt $MinWordLength -or $PopularWords.ContainsKey($word))
        {
            $word = Get-RandomWord $MinSyllables $MaxSyllables
        }
        
        # Check the popularity with Bing
        $countint = Get-BingCount $word
        
        #Write-Host ("{0} --> {1}" -F $word, $countint)

        if($countint -ge $MinPopularity)
        {
            #Write-Host ("{0} --> {1}" -F $word, $countint)
            $PopularWords[$word] = $countint
            $NewProgressLine = ("Progress: {0,7:P0}" -F ($PopularWords.Count/$NumberOfWords))
            if($LastProgressLine -ne $NewProgressLine)
            {
                Write-Host $NewProgressLine
                $LastProgressLine = $NewProgressLine
            }
        }
    }

    # Quit Internet Explorer
    $ie.quit();

    return $PopularWords
}

$PopularWords = DiscoverPopularWords -NumberOfWords $TotalNumberOfWords -MinWordLength $MinimumWordLength
foreach($WordKeyPair in ($PopularWords.GetEnumerator() | Sort -Property Value -Descending))
{   
    # Select Color based on popularity. 
    if     ($WordKeyPair.Value -eq 0)       { $color = "white"  }
    elseif ($WordKeyPair.Value -lt 1000)    { $color = "green"  }
    elseif ($WordKeyPair.Value -lt 10000)   { $color = "yellow" }
    else                                    { $color = "red"    } 

    # Write the info with the right color
    Write-Host ("{0} --> {1}" -F $WordKeyPair.Key, $WordKeyPair.Value) -ForegroundColor $color
}
($PopularWords.GetEnumerator() | Sort -Property Value -Descending).Key | Out-File -FilePath $OutputFilePath -Encoding utf8
