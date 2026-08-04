require "uri"
require "json"
require "net/http"

url = URI("https://api.dhan.co/v2/charts/rollingoption")

https = Net::HTTP.new(url.host, url.port)
https.use_ssl = true

request = Net::HTTP::Post.new(url)
request["Content-Type"] = "application/json"
request["Accept"] = "application/json"
request["access-token"] = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzUxMiJ9.eyJpc3MiOiJkaGFuIiwicGFydG5lcklkIjoiIiwiZXhwIjoxNzg0NTc0MjY5LCJpYXQiOjE3ODQ0ODc4NjksInRva2VuQ29uc3VtZXJUeXBlIjoiQVBQIiwiZGhhbkNsaWVudElkIjoiMTEwNDIxNjMwOCJ9.8sMbGEaEnNT_Z2jTOEGE9wAErpDmCK1jHBgVfBwCwZP7BXQ9CU7Kmas4XGrBs4TnaKZq0L1Pv-jkT3LqkKN8hQ"
request.body = JSON.dump({
  "exchangeSegment": "NSE_FNO",
  "interval": "1",
  "securityId": "13",
  "instrument": "OPTIDX",
  "expiryFlag": "WEEK",
  "expiryCode": "1",
  "strike": "ATM, ATM+10, ATM-10",
  "drvOptionType": "CALL",
  "requiredData": [ "open","high","low","close","iv","volume","strike","oi","spot"],
  "fromDate": "2026-06-20",
  "toDate": "2026-07-20"
})

response = https.request(request)
puts response.read_body