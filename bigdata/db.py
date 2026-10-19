"""Shared MySQL connection for the Big Data scripts. Reads the same settings as scripts/lib.sh and .env.example:
DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME, and DB_SSL_CA (path to Aiven's ca.pem, optional) . Needs: pip install pymysql"""
import os, pymysql

def connect():
    kw = dict(host=os.environ.get("DB_HOST", "127.0.0.1"), port=int(os.environ.get("DB_PORT", "3306")),
              user=os.environ.get("DB_USER", "root"), password=os.environ.get("DB_PASSWORD", ""),
              database=os.environ.get("DB_NAME", "ecommerce"), charset="utf8mb4")
    ca = os.environ.get("DB_SSL_CA")
    if ca:
        kw["ssl_ca"] = ca                                   # verify the server certificate
    elif os.environ.get("DB_SSL_MODE", "").upper() in ("REQUIRED", "VERIFY_CA", "VERIFY_IDENTITY"):
        kw["ssl"] = {"check_hostname": False}                # encrypted, certificate not checked (Aiven default)
    return pymysql.connect(**kw)
