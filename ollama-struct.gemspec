
# File: ollama-struct.gemspec

Gem::Specification.new do |spec|
  spec.name          = "ollama-struct"
  spec.version       = "0.1.5"
  spec.authors       = ["Joshua Harding"]
  spec.email         = ["josh@statewidesoftware.com"]

  spec.summary       = "Ruby client for Ollama structured outputs"
  spec.description   = "A Ruby gem that simplifies working with Ollama's structured output API"
  spec.homepage      = "https://github.com/jhstatewide/ollama-struct"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.files         = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_dependency "ostruct", "~> 0.5"
end
