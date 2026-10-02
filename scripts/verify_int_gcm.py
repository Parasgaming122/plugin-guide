#!/usr/bin/env python3
"""Independent GCM implementation using integer arithmetic to establish ground truth."""
import base64
import glob
import json


def str_to_poly(b):
    """bit string -> int, where b_0 (MSB of byte 0) is coeff of x^0."""
    v = 0
    for i in range(128):
        if (b[i // 8] >> (7 - i % 8)) & 1:
            v |= 1 << i
    return v


def poly_to_str(v):
    b = bytearray(16)
    for i in range(128):
        if (v >> i) & 1:
            b[i // 8] |= 1 << (7 - i % 8)
    return bytes(b)


def gf128_mult(a_str, b_str):
    """Carry-less multiply then reduce mod x^128+x^7+x^2+x+1."""
    a = str_to_poly(a_str)
    bb = str_to_poly(b_str)
    z = 0
    for i in range(128):
        if (a >> i) & 1:
            z ^= bb << i
    # reduce: x^128 = x^7+x^2+x+1 = 0x87
    for i in range(255, 127, -1):
        if (z >> i) & 1:
            z ^= (0x87) << (i - 128)
    return poly_to_str(z)


# sanity: identity
ident = poly_to_str(1)
print("identity str:", ident.hex(), "(should be 80000000000000000000000000000000)")
zero = bytes(16)
print("0*0 =", gf128_mult(zero, zero).hex())
print("1*H == H:", gf128_mult(ident, b"\x11" * 16).hex(), "vs", (b"\x11" * 16).hex())

# Verify against WTR-Lab samples with full tag check
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

KEY = b"IJAFUUxjM25hyzL2AZrn0wl7cESED6Ru"


def aes_ecb(block):
    c = Cipher(algorithms.AES(KEY), modes.ECB())
    e = c.encryptor()
    return e.update(block) + e.finalize()


def ghash(data):
    assert len(data) % 16 == 0
    H = aes_ecb(bytes(16))
    Y = bytes(16)
    for i in range(0, len(data), 16):
        blk = data[i:i + 16]
        x = bytes(a ^ b for a, b in zip(Y, blk))
        Y = gf128_mult(x, H)
    return Y


fn = sorted(glob.glob('/home/z/my-project/wtrlab-analysis/enc_*.json'))[0]
d = json.load(open(fn))
body = d['data']['data']['body']
parts = body[4:].split(':')
iv = base64.b64decode(parts[0])
tag = base64.b64decode(parts[1])
ct = base64.b64decode(parts[2])

# J0 via GHASH derivation
len_bits = len(iv) * 8
lb = (0).to_bytes(8, 'big') + len_bits.to_bytes(8, 'big')
pad = b'\x00' * ((16 - len(iv) % 16) % 16)
J0 = ghash(iv + pad + lb)
print("J0 (int-based) =", J0.hex())

# CTR decrypt
plain = bytearray()
counter = int.from_bytes(J0, 'big')
pos = 0
while pos < len(ct):
    counter = (counter & ~0xFFFFFFFF) | ((counter + 1) & 0xFFFFFFFF)
    ks = aes_ecb(counter.to_bytes(16, 'big'))
    n = min(16, len(ct) - pos)
    plain += bytes(a ^ b for a, b in zip(ct[pos:pos + n], ks[:n]))
    pos += n
print("plain[:40] =", bytes(plain[:40]))

# Tag verification (GHASH over padded C, then len block: 0^64 || ct_bit_len)
ct_pad = ct + b'\x00' * ((16 - len(ct) % 16) % 16)
ct_len_bits = len(ct) * 8
lenblk = (0).to_bytes(8, 'big') + ct_len_bits.to_bytes(8, 'big')
tag_calc = ghash(ct_pad + lenblk)
tag_final = bytes(a ^ b for a, b in zip(tag_calc, aes_ecb(J0)))
print("tag match:", tag_final == tag)
print("plain == library result:", bytes(plain) == AESGCM(KEY).decrypt(iv, ct + tag, None))
