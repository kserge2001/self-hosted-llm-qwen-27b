# Bedrock guardrail called by LiteLLM (ApplyGuardrail) on prompts and answers.
# It works on text from any model, including our own vLLM: no Bedrock model is involved.
resource "aws_bedrock_guardrail" "this" {
  name                      = "${var.name}-guardrail"
  description               = "Anonymize personal data and refuse a minimal set of topics"
  blocked_input_messaging   = "Sorry, this request is not allowed by the Astra usage policy."
  blocked_outputs_messaging = "Sorry, the answer was blocked by the Astra usage policy."

  # Personal data is replaced by a tag such as {EMAIL}, not blocked, so the request still works.
  sensitive_information_policy_config {
    dynamic "pii_entities_config" {
      for_each = ["EMAIL", "PHONE", "NAME", "ADDRESS", "US_SOCIAL_SECURITY_NUMBER", "CREDIT_DEBIT_CARD_NUMBER", "AWS_ACCESS_KEY", "AWS_SECRET_KEY"]
      content {
        type   = pii_entities_config.value
        action = "ANONYMIZE"
      }
    }
  }

  # One denied topic, to show the feature. A company adds its own list here.
  topic_policy_config {
    topics_config {
      name       = "investment-advice"
      type       = "DENY"
      definition = "Recommendations about which stocks, funds or cryptocurrencies to buy or sell."
      examples   = ["Which stock should I buy this week?"]
    }
  }
}

# A numbered, frozen version. LiteLLM calls this version, not the editable DRAFT.
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "Created by Terraform"
}
