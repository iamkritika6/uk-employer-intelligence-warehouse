# Hand-check of fuzzy matches

A sample of 24 fuzzy matches, six from each quarter of the similarity range, read
side by side and judged by inspection. Sampling was deterministic
(`row_number() OVER (... ORDER BY md5(name))`) so the same sample can be reproduced.

**This is a judgement by eye, not verified ground truth.** No authoritative list says
which register entry belongs to which company; the verdicts below are what a careful
reader concludes from the two names alone. They are good enough to estimate the order
of magnitude of the error rate, and not good enough to be called a measurement.

| Score | Register name | Matched company | Verdict |
|---|---|---|---|
| 0.800 | indian ocean | iwr indian ocean | **Wrong** - added initials mean a different company |
| 0.813 | social media 92 | media social | **Wrong** |
| 0.821 | valley drive dental practice | valley dental practice | **Wrong** - "drive" dropped, different practice |
| 0.824 | st michaels news | michaels news | Uncertain |
| 0.833 | nyadowa service | nyadowa services | Correct - singular/plural |
| 0.848 | ocean way hospitality services | oceanway hospitality services | Correct - spacing |
| 0.854 | clitheroe cricket bowls and tennis club | clitheroe cricket bowling and tennis club | Correct |
| 0.864 | hd hyundai electric uk | hd hyundai electric | Uncertain - UK arm vs parent |
| 0.875 | goodwins hardware wholesalers london | goodwin s hardware wholesalers london | Correct - apostrophe |
| 0.880 | qrc quality reliable care | quality reliable care | Uncertain - initials prefix |
| 0.889 | m a and brothers convenience store | a and g brothers convenience store | **Wrong** |
| 0.893 | dans news and supermarkets | dans news and supermarket | Correct |
| 0.903 | frontier protection worldwid | frontier protection worldwide | Correct - typo in the register |
| 0.903 | bright smiles dental practice | bright smile dental practice | Correct |
| 0.906 | hellenic foods distribution uk | hellenic food distribution uk | Correct |
| 0.917 | excitation and engineering service | excitation and engineering services | Correct |
| 0.932 | london college of science and management | london college of science and management uk | Uncertain |
| 0.935 | the japan ship owners mutual protection and... | japan ship owners mutual protection and inde... | Correct - truncation |
| 0.967 | fonjock social work practice | fonjock s social work practice | Correct |
| 1.000 | wwl uk | uk wwl | Uncertain |
| 1.000 | the birmingham diocesan board of finance | birmingham diocesan board of finance the | Correct - "the" moved |
| 1.000 | centre for economic and business research | centre for business and economic research | Uncertain |
| 1.000 | taylor thomas | thomas taylor | **Wrong** |
| 1.000 | tierra and mar | mar and tierra | Uncertain |

## Result

| Verdict | Count | Share of sample |
|---|---|---|
| Correct | 12 | 50% |
| Wrong | 5 | 21% |
| Uncertain | 7 | 29% |

So **at least 21% of fuzzy matches are wrong**, and the true figure could be as high as
50% if every uncertain case is also wrong. On 3,311 fuzzy matches that is somewhere
between roughly 700 and 1,650 incorrect links.

Fuzzy matches are 2.61% of all employer names, so this contributes an error of roughly
0.5% to 1.3% across the whole match table.

## The finding that matters: a score of 1.000 does not mean correct

Of the 208 fuzzy matches scoring exactly 1.000, **166 are the same words in a different
order**:

    taylor thomas                              <-> thomas taylor
    tierra and mar                             <-> mar and tierra
    centre for economic and business research  <-> centre for business and economic research

Trigram similarity cuts a string into three-character sequences and compares the sets.
Reordering whole words leaves almost all of those sequences intact, so two names made of
the same words score 1.000 whether or not they are the same organisation. Some
reorderings are harmless ("the" moving to the end). Others, like two surnames swapping
places, are plainly different businesses.

This is a property of the algorithm, not a bug in the data, and it is the single most
important caveat about the matching in this project. A perfect similarity score is not
evidence of a correct match.

## What was done about it

Nothing was deleted or silently filtered. The marts layer treats `exact` and `fuzzy`
matches differently and records the method on every row, so any analysis can state
which basis it rests on. Fuzzy matches are retained with their scores so this check can
be repeated or extended.

A possible improvement, not implemented: compare sorted word sets as well as trigram
similarity, and demote matches that agree only on word content. That would catch the
166 reorderings. It is recorded here as known future work rather than claimed as done.
