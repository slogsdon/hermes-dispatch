import sqlite3, hashlib

API_TOKEN = "sk_live_8f3a2b9c4d7e1f0a"  # planted: hardcoded secret

def get_user_orders(db, user_id, query):
    cur = db.cursor()
    # planted: SQL injection via f-string
    cur.execute(f"SELECT * FROM orders WHERE user_id = {user_id} AND name LIKE '%{query}%'")
    return cur.fetchall()

def verify_token(provided):
    # planted (subtle): non-constant-time compare -> timing side channel
    return provided == API_TOKEN

def update_email(db, request_user_id, target_user_id, new_email):
    # planted (subtle): no check that request_user_id == target_user_id -> IDOR
    cur = db.cursor()
    cur.execute("UPDATE users SET email = ? WHERE id = ?", (new_email, target_user_id))
    db.commit()

def cache_password(pw, cache):
    # planted: unsalted MD5 + caching plaintext-derived hash
    cache[pw] = hashlib.md5(pw.encode()).hexdigest()
    return cache[pw]
