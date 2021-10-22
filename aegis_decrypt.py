#!/usr/bin/env python3

# this depends on the 'cryptography' package
# pip install cryptography

# example usage: ./scripts/decrypt.py --input ./app/src/test/resources/com/beemdevelopment/aegis/importers/aegis_encrypted.json
# password: test

import argparse
import base64
import getpass
import io
import json
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
from cryptography.hazmat.backends import default_backend
import cryptography
backend = default_backend()

def die(msg, code=1):
    print(msg, file=sys.stderr)
    exit(code)

def main():
    parser = argparse.ArgumentParser(description="Decrypt an Aegis vault")
    parser.add_argument("--output", dest="output", default="-", help="output file ('-' for stdout)")
    args = parser.parse_args()

    # parse the Aegis vault file
    data = json.loads("{\"version\":1,\"header\":{\"slots\":[{\"type\":2,\"uuid\":\"49968201-b180-4c6e-9318-da56eb2b2191\",\"key\":\"565225894cb08cbb7419e3cf2910ffe42969cc87f22365f1f9b99d381ffa7af1\",\"key_params\":{\"nonce\":\"f522b7387fa50ada6f973377\",\"tag\":\"f49985a19ee35732b3041cc6d3a6a7e6\"}},{\"type\":1,\"uuid\":\"a8027cea-ec32-46dd-a2a7-fed0cbf08fb8\",\"key\":\"888f1b9a061b59f79c6d53a9c4d016d1c8cc197a6fa618ae07f132668c82e7bd\",\"key_params\":{\"nonce\":\"330786085c930d9fd9ac502c\",\"tag\":\"1b50fcf51d8f22fa249e9ca92afe4830\"},\"n\":32768,\"r\":8,\"p\":1,\"salt\":\"bdcd0b972051a5ad8234952afa215a703a17616c7fc0e2fba3e60be3376c93a4\",\"repaired\":true}],\"params\":{\"nonce\":\"ecaa940abaea8bccae659229\",\"tag\":\"6b40ae6d834145b99a290f019d829754\"}},\"db\":\"/aKgDqGqJGULeo4H3djIPcbzBltdG82nHjkIeXDvfhL4lE+JhH+JyDWv96o/CYlzbT1Ze6Hu0J6DTrKas8Cd1WEoUDuGb0IqNy4SygQsyWUAN7zaAeNg5qPRxt39vAhHUzQnL2AwtruQYLLIJgrZIm5x7nJk5ghsGVYrzdIsKMtJ3rGCrSTdXX18IBIeeU5kmhqTrMjAuALpP6+/qkJIuaO8qY2MruR51YIeIk36ldcx9ntivl1/oNKpdmsXrMklhJPp7aUdusQrRMqwcz+aS7wd+BBJRbfU/yFQnNIVWj9y2jcFfTps7HNw6XouNg3n57cScjtTyDEUfg5lLAPglqSjs8tamA92K98MszV6cPtq64bg7A5V2n8h86T5ToUHUSJ9B6ZUvuvxPtHjb5Yq6RCjZFpoi5BGjoxvQJaf+9vK5qJ1inpt46MdazoG5FnxVBJPg93Rqx5cQWvsJw+OsAkY50l2fZfxhWkS6ODLiSqu5bh2pam1fm9l7d1GoxQzYKa/WEusoFnlBNQuqnCWmZ6WwZghZYZZQEXTynXYi8KpfWCgbmZpGqlX1biVs+mAHzASUVTX8xB6IeuAVHqp3FuPMCuHoq8oW//3qg==\"}"
)

    # ask the user for a password
    password = "Beth2015$".encode("utf-8")

    # extract all password slots from the header
    header = data["header"]
    slots = [slot for slot in header["slots"] if slot["type"] == 1]

    # try the given password on every slot until one succeeds
    master_key = None
    for slot in slots:
        # derive a key from the given password
        kdf = Scrypt(
            salt=bytes.fromhex(slot["salt"]),
            length=32,
            n=slot["n"],
            r=slot["r"],
            p=slot["p"],
            backend=backend
        )
        key = kdf.derive(password)

        print (base64.b64encode(key))

        # try to use the derived key to decrypt the master key
        cipher = AESGCM(key)
        params = slot["key_params"]
        try:
            nonce = bytes.fromhex(params["nonce"])
            print ("nonce:" + str(base64.b64encode(nonce)))
            data_bytes = bytes.fromhex(slot["key"]) + bytes.fromhex(params["tag"])
            print ("master key data: " + str(base64.b64encode(data_bytes)))

            master_key = cipher.decrypt(
                nonce=nonce,
                data=data_bytes,
                associated_data=None
            )
            break
        except cryptography.exceptions.InvalidTag:
            pass

    if master_key is None:
        die("error: unable to decrypt the master key with the given password")

    print ("master key: " + str(base64.b64encode(master_key)))

    # decode the base64 vault contents
    content = base64.b64decode(data["db"])

    # decrypt the vault contents using the master key
    params = header["params"]
    cipher = AESGCM(master_key)

    nonce = bytes.fromhex(params["nonce"])
    data = content + bytes.fromhex(params["tag"])

    print ("nonce:" + str(base64.b64encode(nonce)))
    print ("data: " + str(base64.b64encode(data)))

    db = cipher.decrypt(
        nonce=nonce,
        data=data,
        associated_data=None
    )

    db = db.decode("utf-8")
    if args.output != "-":
        with io.open(args.output, "w") as f:
            f.write(db)
    else:
        print(db)

if __name__ == "__main__":
    main()
