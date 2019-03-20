# Hashcat-Stuffs
Collection of hashcat lists and things.

### Hashcat-Stuffs/masks/9_plus_microsoft_complexity_top_5000_masks.txt
List of the top 5,000 masks created from all publicly available password dumps, with 9+ characters, meeting Microsoft password complexity requirements (6+ characters in length, 3/4 categories: A-Z, a-z, 0-9, special characters). The collection of generated masks was sorted by a score of computational complexity versus occurrence, selecting the top 5,000 most occurring and easiest to run through. This creates mask attacks that make it through the most frequently used key-spaces, as fast as possible. It should be used after running through the entire 8-character bruteforce.

### Hashcat-Stuffs/masks/9_plus_top_5000_masks.txt
List of the top 5,000 masks created from all publicly available password dumps, with 9+ characters. The collection of generated masks was sorted by a score of computational complexity versus occurrence, selecting the top 5,000 most occurring and easiest to run through. This creates mask attacks that make it through the most frequently used key-spaces, as fast as possible. It should be used after running through the entire 8-character bruteforce.

### Hashcat-Stuffs/Rules/RuleList.rule
List of combined rules from all publicly available rule lists out there, plus some extra rules from a very long session of plugging random rules in. I believe they are sorted by occurrence, which is heavily influenced by what rules worked while cracking a very large set of hashes; rules were recorded in a log each time they individually lead to a successful match. These rules and the randomly generated ones were run on a combined password list of all publicly available password dumps.
