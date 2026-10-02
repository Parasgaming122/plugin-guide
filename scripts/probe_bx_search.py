#!/usr/bin/env python3
"""Probe bixiange EmpireCMS search: POST /e/search/indexpage.php with GBK-encoded keyword."""
import http.client
import ssl
import urllib.parse

HOST = "www.bixiange.top"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"
ctx = ssl.create_default_context()


def post_search(keyword_gbk: bytes):
    body = b"keyboard=" + urllib.parse.quote_from_bytes(keyword_gbk, safe="").encode("ascii") \
           + b"&show=title&classid=0"
    conn = http.client.HTTPSConnection(HOST, timeout=40, context=ctx)
    conn.request("POST", "/e/search/indexpage.php", body=body, headers={
        "User-Agent": UA,
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "text/html,application/xhtml+xml",
        "Referer": f"https://{HOST}/",
        "Accept-Language": "zh-CN,zh;q=0.9",
    })
    r = conn.getresponse()
    raw = r.read()
    return r.status, dict(r.getheaders()), raw


def main():
    kw = "家父永乐".encode("gbk")
    status, headers, raw = post_search(kw)
    print("STATUS:", status)
    print("LOCATION:", headers.get("Location") or headers.get("location"))
    print("CONTENT-TYPE:", headers.get("Content-Type"))
    text = raw.decode("gbk", errors="replace")
    print("BODY[:1500]:")
    print(text[:1500])


if __name__ == "__main__":
    main()
