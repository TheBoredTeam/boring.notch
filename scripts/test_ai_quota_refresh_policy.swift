import Foundation

@main
struct AIQuotaRefreshPolicyTest {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000)
        var policy = AIQuotaRefreshPolicy()

        assert(policy.canRequest(.claude, now: now), "Claude should be requestable before any rate limit")

        policy.recordRateLimit(.claude, retryAfter: 300, now: now)
        assert(!policy.canRequest(.claude, now: now.addingTimeInterval(299)), "Claude should wait until retry-after expires")
        assert(policy.canRequest(.claude, now: now.addingTimeInterval(300)), "Claude should be requestable when retry-after expires")
        assert(policy.canRequest(.codex, now: now), "Claude rate limit must not block Codex")

        policy.recordRateLimit(.claude, retryAfter: nil, now: now)
        assert(!policy.canRequest(.claude, now: now.addingTimeInterval(1_799)), "Claude should use default backoff when retry-after is missing")
        assert(policy.canRequest(.claude, now: now.addingTimeInterval(1_800)), "Claude default backoff should expire after 30 minutes")

        policy.recordRateLimit(.claude, retryAfter: 300, now: now)
        policy.recordSuccess(.claude)
        assert(policy.canRequest(.claude, now: now), "Successful refresh should clear Claude backoff")
    }
}
