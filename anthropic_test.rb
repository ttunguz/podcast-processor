require 'anthropic'

Anthropic.configure do |config|
  config.access_token = ENV.fetch("ANTHROPIC_API_KEY")
end

client = Anthropic::Client.new

response = client.messages(
  parameters: {
    model: "claude-3-opus-20240229",
    messages: [
      {
        role: "user",
        content: "Hello! Please respond with 'Test successful' if you receive this message."
      }
    ],
    max_tokens: 1024
  }
)

# The response content is in the first content block's text
puts response["content"][0]["text"]