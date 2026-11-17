# Test bank data

`blz.properties` is a made-up bank list in the format of hbci4java, with the header of `scripts/bank-data.py build`: the serial and the version of hbci4java. `scripts/bank-data.py sign` signed it with the test update key of `Fixtures/update`, which wrote `blz.properties.sig`. `BankDataTests` checks it with the public test key, so the script of the workflow and the check of the app agree on the format of the signature.

To serve test files to a Debug build, copy both files into a folder, change them and raise the serial, sign them with the same command, and serve the folder with `python3 -m http.server --bind 127.0.0.1`. `MONETEN_BANK_DATA_URL` names that folder for the app.
