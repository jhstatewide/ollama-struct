#!/usr/bin/env ruby
# File: examples/travel_planner.rb

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'ollama-struct', path: '.'
  gem 'optparse'
  gem 'terminal-table'
  gem 'colorize'
end

options = {
  host: 'localhost',
  port: 11434,
  model: 'llama3.2',
  days: 3,
  destination: 'Tokyo, Japan'
}

# Parse command line arguments
OptionParser.new do |opts|
  opts.banner = "Usage: travel_planner.rb [options]"

  opts.on("-h", "--host HOST", "Ollama host (default: localhost)") do |h|
    options[:host] = h
  end

  opts.on("-p", "--port PORT", Integer, "Ollama port (default: 11434)") do |p|
    options[:port] = p
  end

  opts.on("-m", "--model MODEL", "Model to use (default: llama3.2)") do |m|
    options[:model] = m
  end

  opts.on("-d", "--days DAYS", Integer, "Number of days (default: 3)") do |d|
    options[:days] = d
  end

  opts.on("-D", "--destination LOCATION", "Destination (default: Tokyo, Japan)") do |d|
    options[:destination] = d
  end
end.parse!

# Create client instance
client = Ollama::Struct.new(
  model: options[:model],
  host: options[:host],
  port: options[:port]
)

# Define a complex travel itinerary schema
# This showcases deeply nested structured data
travel_schema = Ollama::Schema.object(
  properties: {
    destination: Ollama::Schema.object(
      properties: {
        name: Ollama::Schema.string,
        country: Ollama::Schema.string,
        description: Ollama::Schema.string,
        climate: Ollama::Schema.string,
        language: Ollama::Schema.string,
        currency: Ollama::Schema.string,
        best_time_to_visit: Ollama::Schema.string
      },
      required: %w[name country description]
    ),
    itinerary: Ollama::Schema.array(
      Ollama::Schema.object(
        properties: {
          day: Ollama::Schema.integer,
          title: Ollama::Schema.string,
          activities: Ollama::Schema.array(
            Ollama::Schema.object(
              properties: {
                time: Ollama::Schema.string,
                activity: Ollama::Schema.string,
                location: Ollama::Schema.string,
                description: Ollama::Schema.string,
                cost_estimate: Ollama::Schema.object(
                  properties: {
                    amount: Ollama::Schema.number,
                    currency: Ollama::Schema.string
                  },
                  required: %w[amount currency]
                ),
                tags: Ollama::Schema.array(Ollama::Schema.string)
              },
              required: %w[time activity location]
            )
          ),
          accommodation: Ollama::Schema.object(
            properties: {
              name: Ollama::Schema.string,
              type: Ollama::Schema.string,
              description: Ollama::Schema.string,
              location: Ollama::Schema.string
            },
            required: %w[name type]
          )
        },
        required: %w[day title activities]
      )
    ),
    budget_estimate: Ollama::Schema.object(
      properties: {
        total: Ollama::Schema.object(
          properties: {
            amount: Ollama::Schema.number,
            currency: Ollama::Schema.string
          },
          required: %w[amount currency]
        ),
        breakdown: Ollama::Schema.object(
          properties: {
            accommodation: Ollama::Schema.number,
            food: Ollama::Schema.number,
            transportation: Ollama::Schema.number,
            activities: Ollama::Schema.number,
            other: Ollama::Schema.number
          },
          required: %w[accommodation food transportation activities]
        )
      },
      required: %w[total breakdown]
    ),
    packing_list: Ollama::Schema.array(
      Ollama::Schema.object(
        properties: {
          category: Ollama::Schema.string,
          items: Ollama::Schema.array(Ollama::Schema.string)
        },
        required: %w[category items]
      )
    ),
    travel_tips: Ollama::Schema.array(
      Ollama::Schema.object(
        properties: {
          title: Ollama::Schema.string,
          content: Ollama::Schema.string
        },
        required: %w[title content]
      )
    )
  },
  required: %w[destination itinerary budget_estimate packing_list travel_tips]
)

# Prepare the prompt
days = options[:days]
destination = options[:destination]
messages = [{
              role: 'user',
              content: "Create a detailed #{days}-day travel plan for #{destination}. Include daily activities, accommodations, budget estimates, packing suggestions, and travel tips."
            }]

puts "\n#{'=' * 80}".colorize(:light_blue)
puts "📍 Generating #{days}-day travel plan for #{destination}".colorize(:light_yellow)
puts "   Using model: #{options[:model]}".colorize(:light_green)
puts "#{'=' * 80}\n".colorize(:light_blue)

# Make the request with proper error handling
begin
  result = client.chat(
    messages: messages,
    format: travel_schema,
    options: { temperature: 0.7 }
  )

  # Display the result in a nice format
  destination_info = result['destination']
  puts "\n#{'=' * 80}".colorize(:cyan)
  puts "🌎 DESTINATION: #{destination_info['name']}, #{destination_info['country']}".colorize(:light_yellow)
  puts "#{'=' * 80}".colorize(:cyan)
  puts "\n#{destination_info['description']}"
  
  puts "\n📝 Basic Information:".colorize(:light_green)
  info_table = Terminal::Table.new do |t|
    t << ['Climate', destination_info['climate']]
    t << ['Language', destination_info['language']]
    t << ['Currency', destination_info['currency']]
    t << ['Best Time to Visit', destination_info['best_time_to_visit']]
    t.style = { border_x: '=', border_i: 'x' }
  end
  puts info_table
  
  # Display itinerary
  puts "\n📅 Itinerary:".colorize(:light_green)
  result['itinerary'].each do |day|
    puts "\n#{'*' * 50}".colorize(:light_blue)
    puts "Day #{day['day']}: #{day['title']}".colorize(:light_yellow)
    puts "#{'*' * 50}".colorize(:light_blue)
    
    day['activities'].each do |activity|
      puts "\n🕒 #{activity['time']} - #{activity['activity']}".colorize(:light_magenta)
      puts "📍 Location: #{activity['location']}"
      puts "   #{activity['description']}" if activity['description']
      
      if activity['cost_estimate']
        puts "   Cost: #{activity['cost_estimate']['amount']} #{activity['cost_estimate']['currency']}".colorize(:light_red)
      end
      
      if activity['tags'] && !activity['tags'].empty?
        puts "   Tags: #{activity['tags'].join(', ')}".colorize(:light_green)
      end
    end
    
    if day['accommodation']
      puts "\n🏨 Accommodation: #{day['accommodation']['name']} (#{day['accommodation']['type']})".colorize(:light_cyan)
      puts "   Location: #{day['accommodation']['location']}" if day['accommodation']['location']
      puts "   #{day['accommodation']['description']}" if day['accommodation']['description']
    end
  end
  
  # Display budget
  budget = result['budget_estimate']
  puts "\n💰 Budget Estimate:".colorize(:light_green)
  puts "Total: #{budget['total']['amount']} #{budget['total']['currency']}".colorize(:light_red)
  
  budget_table = Terminal::Table.new do |t|
    t.title = "Budget Breakdown"
    t.headings = ['Category', 'Amount']
    t.rows = [
      ['Accommodation', budget['breakdown']['accommodation']],
      ['Food', budget['breakdown']['food']],
      ['Transportation', budget['breakdown']['transportation']],
      ['Activities', budget['breakdown']['activities']],
      ['Other', budget['breakdown']['other']]
    ]
    t.style = { border_x: '-', border_i: '+', alignment: :center }
  end
  puts budget_table
  
  # Display packing list
  puts "\n🧳 Packing List:".colorize(:light_green)
  result['packing_list'].each do |category|
    puts "\n#{category['category']}:".colorize(:light_yellow)
    category['items'].each do |item|
      puts "  • #{item}"
    end
  end
  
  # Display travel tips
  puts "\n💡 Travel Tips:".colorize(:light_green)
  result['travel_tips'].each_with_index do |tip, index|
    puts "\n#{index + 1}. #{tip['title']}".colorize(:light_yellow)
    puts "   #{tip['content']}"
  end
  
rescue Ollama::ConnectionError => e
  puts "Connection Error: #{e.message}".colorize(:red)
  exit 1
rescue Ollama::ModelNotFoundError => e
  puts "Model Error: #{e.message}".colorize(:red)
  puts "Available models can be checked with 'ollama list' command.".colorize(:yellow)
  exit 1
rescue Ollama::APIError => e
  puts "API Error (#{e.status_code}): #{e.message}".colorize(:red)
  exit 1
rescue StandardError => e
  puts "Error: #{e.message}".colorize(:red)
  exit 1
end
