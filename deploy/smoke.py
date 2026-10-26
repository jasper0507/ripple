#!/usr/bin/env python3
"""Exercise the deployed HTTPS frontend and API. Leaves one test account per run."""

import argparse
import http.cookiejar
import json
import secrets
import ssl
import time
import urllib.error
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base_url", nargs="?", default="https://ripple.jasperlab.dev")
    parser.add_argument("--ca", help="CA certificate for isolated local HTTPS verification")
    parser.add_argument("--keep", action="store_true", help="Keep the test post/comment for restart verification")
    parser.add_argument("--verify-post", type=int, help="Only verify a retained post after restarting containers")
    args = parser.parse_args()
    if not args.base_url.startswith("https://"):
        parser.error("HTTPS is required to verify Secure refresh cookies")
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        urllib.request.HTTPCookieProcessor(jar),
        urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=args.ca)),
    )
    token = None

    def request(method, path, body=None, status=200, api=True):
        headers = {
            "Accept": "application/json" if api else "text/html",
            "User-Agent": "Ripple-Deployment-Check/1.0",
        }
        if token:
            headers["Authorization"] = f"Bearer {token}"
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        req = urllib.request.Request(args.base_url.rstrip("/") + path, data=data, headers=headers, method=method)
        try:
            response = opener.open(req, timeout=20)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            payload = response.read()
            if response.status != status:
                raise RuntimeError(f"{method} {path}: expected {status}, got {response.status}")
            if api and payload:
                assert "application/json" in response.headers.get("Content-Type", ""), path
                parsed = json.loads(payload)
                assert parsed.get("code") == "OK", f"Unexpected business result for {path}"
                return parsed.get("data"), response.headers
            return payload, response.headers

    if args.verify_post:
        post, _ = request("GET", f"/api/v1/posts/{args.verify_post}")
        assert post["title"].startswith("Deployment verification"), "Unexpected retained post"
        print(f"Persistence verified: post {args.verify_post}")
        return

    for path in ("/", "/posts/999999999"):
        _, headers = request("GET", path, api=False)
        assert "text/html" in headers.get("Content-Type", ""), path
    request("GET", "/assets/__deployment_missing__.js", status=404, api=False)
    payload, headers = request("GET", "/api/v1/__deployment_missing__", status=404, api=False)
    assert "text/html" not in headers.get("Content-Type", ""), "API 404 became SPA HTML"
    communities, _ = request("GET", "/api/v1/communities")
    assert communities, "Communities were not initialized"

    username = "deploy" + secrets.token_hex(6)
    password = "Aa1!" + secrets.token_hex(7)
    request("POST", "/api/v1/signup", {"username": username, "password": password, "confirm_password": password}, status=201)
    login, headers = request("POST", "/api/v1/login", {"username": username, "password": password})
    token = login["access_token"]
    cookie_header = headers.get("Set-Cookie", "").lower()
    assert "httponly" in cookie_header and "secure" in cookie_header and "samesite=lax" in cookie_header
    original_cookie = next(cookie.value for cookie in jar if cookie.name == "refresh_token")
    post_id = comment_id = None
    try:
        post, _ = request("POST", "/api/v1/posts", {
            "title": "Deployment verification " + username,
            "content": "HTTPS, cookies, MySQL, Redis and Outbox verification.",
            "community_id": communities[0]["id"],
        }, status=201)
        post_id = post["id"]
        comment, _ = request("POST", f"/api/v1/posts/{post_id}/comments", {"content": "Deployment verification"}, status=201)
        comment_id = comment["id"]
        request("PUT", f"/api/v1/posts/{post_id}/vote", {"direction": 1})
        vote, _ = request("GET", f"/api/v1/posts/{post_id}/vote")
        assert vote["direction"] == 1
        deadline = time.monotonic() + 15
        while True:
            listing, _ = request("GET", "/api/v1/posts?sort=time")
            if any(item["id"] == post_id for item in listing["items"]):
                break
            if time.monotonic() >= deadline:
                raise RuntimeError("Outbox did not project the test post into Redis within 15 seconds")
            time.sleep(0.5)
        token = None
        refreshed, _ = request("POST", "/api/v1/refresh")
        token = refreshed["access_token"]
        assert next(cookie.value for cookie in jar if cookie.name == "refresh_token") != original_cookie
    finally:
        if token and not args.keep:
            if comment_id:
                request("DELETE", f"/api/v1/comments/{comment_id}", status=204)
            if post_id:
                request("DELETE", f"/api/v1/posts/{post_id}", status=204)
    request("POST", "/api/v1/logout", status=204)
    assert not any(cookie.name == "refresh_token" for cookie in jar)
    print(f"HTTPS, SPA/API routing, signup/login, post/comment/vote, Outbox and cookie rotation passed. Account: {username}")
    if args.keep:
        print(f"Retained post: {post_id}; comment: {comment_id}")


if __name__ == "__main__":
    main()
