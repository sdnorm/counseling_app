require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "a content security policy is sent" do
    get new_session_path
    assert_response :success
    assert response.headers["Content-Security-Policy"].present?,
      "every response must carry a CSP header"
  end

  test "the policy locks down the dangerous directives" do
    get new_session_path
    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "default-src 'self'"
    assert_includes csp, "object-src 'none'"
    assert_includes csp, "base-uri 'self'"
    assert_includes csp, "frame-ancestors 'none'"
  end

  test "scripts are nonce-based rather than unsafe-inline" do
    get new_session_path
    csp = response.headers["Content-Security-Policy"]

    assert_match(/script-src [^;]*'nonce-/, csp)
    assert_no_match(/script-src [^;]*'unsafe-inline'/, csp)
    assert_no_match(/script-src [^;]*'unsafe-eval'/, csp)
  end

  test "the importmap and module scripts carry the nonce" do
    get root_url
    follow_redirect!
    nonce = response.body[/<meta name="csp-nonce" content="([^"]+)"/, 1]
    assert nonce.present?, "csp_meta_tag must expose the nonce"

    assert_includes response.body, %(type="importmap")
    response.body.scan(/<script([^>]*)>/) do |attrs|
      assert_includes attrs.first, %(nonce="#{nonce}"),
        "every script tag must carry the CSP nonce or it will be blocked"
    end
  end

  test "the Google Fonts stylesheet origin is allowed" do
    get new_session_path
    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "https://fonts.googleapis.com"
    assert_includes csp, "https://fonts.gstatic.com"
    assert_includes csp, "style-src 'self' 'unsafe-inline'"
  end
end
