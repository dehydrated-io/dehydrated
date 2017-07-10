### challenges.txt

All the challenges that are requested from letsencrypt are stored in file `challenges.txt`.
The format of each line is "${altname} ${challenge_token} ${challenge_uri} ${keyauth} ${keyauth_hook}"

If the file is present in the folder, those challenges are treated as failed challenge. dehydrated will take challenges from `challenges.txt` instead of requesting it from letsencrypt server
