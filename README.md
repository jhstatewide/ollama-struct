# ollama-struct

Unlock the full power of large language models with structured outputs in Ruby. 

`ollama-struct` is a Ruby gem that makes it easy to work with Ollama's structured output capability, allowing you to transform free-form LLM responses into well-defined, structured data ready for your application.

> **Important:** This gem does not include any language models. It requires [Ollama](https://ollama.ai/) to be installed and running either on your local machine or accessible on your network.

## Why ollama-struct?

Working with LLMs often means dealing with unpredictable, free-form text. When you need reliable, structured data for your applications, this can be challenging. `ollama-struct`:

- **Enforces Data Structure**: Define exactly what data you need with a simple schema
- **Handles Validation**: Automatically validates responses against your schema
- **Smart Retry Logic**: Intelligently retries with targeted prompts when data is incomplete
- **Failsafe Defaults**: Apply sensible defaults for missing fields when needed
- **Clean Error Handling**: Provides clear, actionable errors for troubleshooting

## Quick Start

### Installation

Add to your Gemfile:

```ruby
gem 'ollama-struct'
```

Or install directly:

```bash
gem install ollama-struct
```

### Basic Usage

Here's a simple example that gets structured information about a country:

```ruby
require 'ollama/struct'

# Create a client
client = Ollama::Struct.new(model: 'llama3')

# Define your schema (what structure you want back)
country_schema = Ollama::Schema.object(
  properties: {
    name: Ollama::Schema.string,
    capital: Ollama::Schema.string,
    population: Ollama::Schema.integer,
    languages: Ollama::Schema.array(Ollama::Schema.string, min: 1)
  },
  required: %w[name capital population]
)

# Make your request
result = client.chat(
  messages: [{ role: 'user', content: 'Tell me about Canada.' }],
  format: country_schema
)

# Use the structured data in your application
puts "Country: #{result['name']}"
puts "Capital: #{result['capital']}"
puts "Population: #{result['population'].to_s(:delimited)}"
puts "Languages: #{result['languages'].join(', ')}"
```

## Practical Examples

### 1. Generating a Character for an RPG Game

The included [character_generator.rb](./examples/character_generator.rb) example shows how to create a fully-fledged RPG character with attributes, abilities, equipment, and backstory:

```bash
# Basic usage
./examples/character_generator.rb

# Generate a specific character
./examples/character_generator.rb --race "Elf" --class "Wizard" --level 12
```

### 2. Creating a Travel Itinerary

The [travel_planner.rb](./examples/travel_planner.rb) example demonstrates generating a complex multi-day travel plan with activities, accommodation, budget, and more:

```bash
# Generate a 3-day Tokyo trip
./examples/travel_planner.rb --destination "Tokyo, Japan" --days 3

# Custom parameters
./examples/travel_planner.rb --destination "Paris, France" --days 5 --model mistral
```

### 3. Simple Joke Generator

For a simpler example, [joke_generator.rb](./examples/joke_generator.rb) shows how to create a basic joke with setup and punchline:

```bash
./examples/joke_generator.rb
```

## Advanced Features

### Handling Missing Data

`ollama-struct` can automatically retry with targeted prompts when the LLM response is incomplete:

```ruby
result = client.chat(
  messages: messages,
  format: travel_schema,
  options: { 
    max_retries: 2,              # Try up to 2 more times if data is incomplete
    ensure_complete: true,       # Validate data completeness
    temperature: 0.7,            # Control randomness
    targeted_retries: true,      # Use targeted prompts about missing fields
    defaults: {                  # Fall back to these defaults if needed
      'destination' => {
        'name' => 'Tokyo',
        'country' => 'Japan'
      }
    }
  }
)
```

### Strict Mode

For applications where data integrity is critical, use strict mode:

```ruby
client.chat(
  messages: messages,
  format: user_schema,
  options: { 
    ensure_complete: true,
    strict: true  # Raises IncompleteResponseError instead of using defaults
  }
)
```

## Compatibility

> **Important:** This gem does not include any language models. It requires a running Ollama server with your desired models installed either on the same computer or on another machine in your network.

- Works with any Ollama model that supports JSON output
- Compatible with Ruby 2.6+
- Requires [Ollama](https://ollama.ai/) to be installed and running
- Can connect to a local Ollama server (default) or a remote Ollama server via the network

### Ollama Setup

1. [Install Ollama](https://ollama.ai/download) on your system or a server in your network
2. Install the models you want to use: `ollama pull llama3`
3. Ensure the Ollama server is running before using this gem

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is available as open source under the terms of the [MIT License](LICENSE).

