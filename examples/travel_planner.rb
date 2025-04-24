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
  destination: 'Tokyo, Japan',
  retries: 2,
  temperature: 0.7,
  min_activities: 4,
  max_activities: 6,
  strict: false,
  targeted_retries: true,
  timeout: 300 # Default to 5 minutes
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
  
  opts.on("-r", "--retries COUNT", Integer, "Number of retries for incomplete data (default: 2)") do |r|
    options[:retries] = r
  end
  
  opts.on("-t", "--temperature TEMP", Float, "Temperature for generation (default: 0.7)") do |t|
    options[:temperature] = t
  end
  
  opts.on("--debug", "Enable debug output") do 
    options[:debug] = true
  end

  opts.on("--min-activities COUNT", Integer, "Minimum activities per day (default: 4)") do |count|
    options[:min_activities] = count
  end
  
  opts.on("--max-activities COUNT", Integer, "Maximum activities per day (default: 6)") do |count|
    options[:max_activities] = count
  end
  
  opts.on("--exact-activities COUNT", Integer, "Exact number of activities per day") do |count|
    options[:exact_activities] = count
  end

  opts.on("--strict", "Raise exception instead of using defaults for incomplete data") do
    options[:strict] = true
  end
  
  opts.on("--no-targeted-retries", "Disable targeted prompts about missing fields") do
    options[:targeted_retries] = false
  end

  opts.on("--timeout SECONDS", Integer, "Request timeout in seconds (default: 300)") do |t|
    options[:timeout] = t
  end
end.parse!

# Helper method to fix or standardize time formats
def format_time(time_str)
  # Check if time string is missing the hour at the beginning (e.g. ":30-10:30")
  if time_str.start_with?(":")
    "9#{time_str}" # Default to 9am if hour is missing
  # Check if time range is missing (e.g. just "10:00")
  elsif !time_str.include?("-") && time_str.include?(":")
    "#{time_str}-#{time_str.split(':').first.to_i + 1}:00" # Add 1 hour duration
  # Check if time format is missing colons (e.g. "900-1030")
  elsif time_str.match?(/^\d{3,4}-\d{3,4}$/)
    times = time_str.split('-')
    "#{times[0][0..-3]}:#{times[0][-2..-1]}-#{times[1][0..-3]}:#{times[1][-2..-1]}"
  # Check if no format at all (e.g. "Morning")
  elsif !time_str.match?(/\d/) && !time_str.include?("-")
    case time_str.downcase
    when "morning" then "9:00-12:00"
    when "afternoon" then "13:00-17:00"
    when "evening" then "18:00-21:00"
    when "night" then "19:00-22:00"
    else "#{time_str} (time)"
    end
  else
    time_str
  end
end

# Create client instance with custom timeout
client = Ollama::Struct.new(
  model: options[:model],
  host: options[:host],
  port: options[:port],
  timeout: options[:timeout]
)

# Define a complex travel itinerary schema
# This showcases deeply nested structured data with array quantity constraints
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
          activities: options[:exact_activities] ? 
            Ollama::Schema.array(
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
                  tags: Ollama::Schema.array(Ollama::Schema.string, min: 1, max: 3)
                },
                required: %w[time activity location]
              ),
              exact: options[:exact_activities]
            ) :
            Ollama::Schema.array(
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
                  tags: Ollama::Schema.array(Ollama::Schema.string, min: 1, max: 3)
                },
                required: %w[time activity location]
              ),
              min: options[:min_activities],
              max: options[:max_activities]
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
      ),
      exact: options[:days]
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
          items: Ollama::Schema.array(Ollama::Schema.string, min: 3)
        },
        required: %w[category items]
      ),
      min: 3
    ),
    travel_tips: Ollama::Schema.array(
      Ollama::Schema.object(
        properties: {
          title: Ollama::Schema.string,
          content: Ollama::Schema.string
        },
        required: %w[title content]
      ),
      min: 3,
      max: 5
    )
  },
  required: %w[destination itinerary budget_estimate packing_list travel_tips]
)

# Prepare default values based on the destination
days = options[:days]
destination = options[:destination]
destination_name = destination.split(',').first.strip
destination_country = destination.split(',').last.strip

# Define defaults to use if the model can't generate complete information
defaults = {
  'destination' => {
    'name' => destination_name,
    'country' => destination_country,
    'description' => "A wonderful place to visit with many attractions",
    'climate' => "Varies by season; summers are warm and humid, winters are cold",
    'language' => "English",
    'currency' => "USD (US Dollar)",
    'best_time_to_visit' => "Late spring (May-June) or early fall (September-October)"
  }
}

# Prepare the prompt
activity_count = options[:exact_activities] ? 
  "exactly #{options[:exact_activities]}" : 
  "#{options[:min_activities]}-#{options[:max_activities]}"

prompt_template = <<-PROMPT
Create a detailed #{days}-day travel plan for #{destination}. 

Your response MUST include:
1. Detailed destination information:
   - Full name and country
   - Descriptive paragraph about the destination
   - Climate information
   - Primary language spoken
   - Currency used
   - Best time to visit

2. A day-by-day itinerary with #{activity_count} activities per day:
   - Each day must have a clear title/theme
   - Each activity needs a specific time range (e.g. "9:00-11:00")
   - Each activity needs a specific location with street address if applicable
   - Brief description for each activity

3. Accommodation details for each day
4. Realistic budget estimates in appropriate currency
5. Packing list organized by category (at least 3 categories with 3+ items each)
6. At least 3 practical travel tips specific to this destination

Be thorough and detailed - don't leave any fields empty.
PROMPT

messages = [{
  role: 'user',
  content: prompt_template
}]

puts "\n#{'=' * 80}".colorize(:bright_blue)
puts "📍 Generating #{days}-day travel plan for #{destination}".colorize(:bright_yellow)
puts "   Using model: #{options[:model]} with #{activity_count} activities per day".colorize(:bright_green)
puts "   Timeout: #{options[:timeout]} seconds (use --timeout to increase if needed)".colorize(:cyan) if options[:debug]
puts "#{'=' * 80}\n".colorize(:bright_blue)

# Add a progress indicator for long-running requests
unless options[:debug]
  spinner_chars = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
  spinner_thread = Thread.new do
    i = 0
    start_time = Time.now
    loop do
      elapsed = Time.now - start_time
      remaining = [options[:timeout] - elapsed, 0].max
      print "\r#{spinner_chars[i % spinner_chars.length]} Working (#{elapsed.to_i}s elapsed, timeout: #{options[:timeout]}s)...  "
      if elapsed > options[:timeout] * 0.8 && elapsed <= options[:timeout]
        print "⚠️  Approaching timeout limit...".colorize(:yellow)
      end
      i += 1
      sleep 0.1
    end
  end
end

# Make the request with proper error handling, using library's built-in validation
begin
  # Let the library handle validation and retries with new options
  result = client.chat(
    messages: messages,
    format: travel_schema,
    options: { 
      temperature: options[:temperature],
      max_retries: options[:retries],
      ensure_complete: true,
      defaults: defaults,
      strict: options[:strict],
      targeted_retries: options[:targeted_retries]
    }
  )

  # Stop the spinner if it's running
  if defined?(spinner_thread) && spinner_thread
    spinner_thread.kill
    print "\r" + " " * 80 + "\r" # Clear the spinner line
  end

  # Post-process the result to fix any formatting issues with times
  result['itinerary'].each do |day|
    day['activities'].each do |activity|
      # Fix any improperly formatted time strings
      activity['time'] = format_time(activity['time']) if activity['time']
    end
  end

  # Ensure destination information is complete
  result['destination']['climate'] ||= defaults['destination']['climate']
  result['destination']['language'] ||= defaults['destination']['language'] 
  result['destination']['currency'] ||= defaults['destination']['currency']
  result['destination']['best_time_to_visit'] ||= defaults['destination']['best_time_to_visit']
  
  # Fill in with additional destination-specific information based on the location
  case destination.downcase
  when /new bedford/
    result['destination']['climate'] = "Humid continental; warm summers and cold winters" if result['destination']['climate'].to_s.strip.empty?
    result['destination']['language'] = "English" if result['destination']['language'].to_s.strip.empty?
    result['destination']['currency'] = "USD (US Dollar)" if result['destination']['currency'].to_s.strip.empty?
    result['destination']['best_time_to_visit'] = "Summer (June-August) or early fall (September)" if result['destination']['best_time_to_visit'].to_s.strip.empty?
  when /tokyo/
    result['destination']['climate'] = "Humid subtropical; hot summers and mild winters" if result['destination']['climate'].to_s.strip.empty?
    result['destination']['language'] = "Japanese" if result['destination']['language'].to_s.strip.empty?
    result['destination']['currency'] = "JPY (Japanese Yen)" if result['destination']['currency'].to_s.strip.empty?
    result['destination']['best_time_to_visit'] = "Spring (March-May) or fall (September-November)" if result['destination']['best_time_to_visit'].to_s.strip.empty?
  when /paris/
    result['destination']['climate'] = "Temperate oceanic; mild, moderately wet all year" if result['destination']['climate'].to_s.strip.empty?
    result['destination']['language'] = "French" if result['destination']['language'].to_s.strip.empty?
    result['destination']['currency'] = "EUR (Euro)" if result['destination']['currency'].to_s.strip.empty?
    result['destination']['best_time_to_visit'] = "Spring (April-June) or fall (September-October)" if result['destination']['best_time_to_visit'].to_s.strip.empty?
  # Add more destinations as needed
  end

  # Display the result in a nice format
  destination_info = result['destination']
  puts "\n#{'=' * 80}".colorize(:cyan)
  puts "🌎 DESTINATION: #{destination_info['name']}, #{destination_info['country']}".colorize(:bright_yellow)
  puts "#{'=' * 80}".colorize(:cyan)
  puts "\n#{destination_info['description']}"
  
  puts "\n📝 Basic Information:".colorize(:bright_green)
  info_table = Terminal::Table.new do |t|
    t << ['Climate', destination_info['climate']]
    t << ['Language', destination_info['language']]
    t << ['Currency', destination_info['currency']]
    t << ['Best Time to Visit', destination_info['best_time_to_visit']]
    t.style = { border_x: '=', border_i: 'x' }
  end
  puts info_table
  
  # Display itinerary
  puts "\n📅 Itinerary:".colorize(:bright_green)
  result['itinerary'].each do |day|
    puts "\n#{'*' * 50}".colorize(:bright_blue)
    puts "Day #{day['day']}: #{day['title']}".colorize(:bright_yellow)
    puts "#{'*' * 50}".colorize(:bright_blue)
    
    day['activities'].each do |activity|
      puts "\n🕒 #{activity['time']} - #{activity['activity']}".colorize(:bright_magenta)
      puts "📍 Location: #{activity['location']}"
      puts "   #{activity['description']}" if activity['description']
      
      if activity['cost_estimate']
        puts "   Cost: #{activity['cost_estimate']['amount']} #{activity['cost_estimate']['currency']}".colorize(:bright_red)
      end
      
      if activity['tags'] && !activity['tags'].empty?
        puts "   Tags: #{activity['tags'].join(', ')}".colorize(:bright_green)
      end
    end
    
    if day['accommodation']
      puts "\n🏨 Accommodation: #{day['accommodation']['name']} (#{day['accommodation']['type']})".colorize(:bright_cyan)
      puts "   Location: #{day['accommodation']['location']}" if day['accommodation']['location']
      puts "   #{day['accommodation']['description']}" if day['accommodation']['description']
    end
  end
  
  # Display budget
  budget = result['budget_estimate']
  puts "\n💰 Budget Estimate:".colorize(:bright_green)
  puts "Total: #{budget['total']['amount']} #{budget['total']['currency']}".colorize(:bright_red)
  
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
  puts "\n🧳 Packing List:".colorize(:bright_green)
  result['packing_list'].each do |category|
    puts "\n#{category['category']}:".colorize(:bright_yellow)
    category['items'].each do |item|
      puts "  • #{item}"
    end
  end
  
  # Display travel tips
  puts "\n💡 Travel Tips:".colorize(:bright_green)
  result['travel_tips'].each_with_index do |tip, index|
    puts "\n#{index + 1}. #{tip['title']}".colorize(:bright_yellow)
    puts "   #{tip['content']}"
  end
  
rescue Ollama::TimeoutError => e
  # Stop the spinner if it's running
  if defined?(spinner_thread) && spinner_thread
    spinner_thread.kill
    print "\r" + " " * 80 + "\r" # Clear the spinner line
  end
  
  puts "\n#{'!' * 80}".colorize(:red)
  puts "TIMEOUT ERROR: The request timed out after #{e.timeout_seconds} seconds.".colorize(:red)
  puts "\nSuggestions:".colorize(:yellow)
  puts "  1. Increase the timeout limit: --timeout #{e.timeout_seconds * 2}".colorize(:yellow)
  puts "  2. Simplify your request (fewer days or simpler destination)".colorize(:yellow)
  puts "  3. Check if the Ollama server is under heavy load".colorize(:yellow)
  puts "  4. Try a different model that might be faster".colorize(:yellow)
  exit 1
rescue Ollama::IncompleteResponseError => e
  # Stop the spinner if it's running
  if defined?(spinner_thread) && spinner_thread
    spinner_thread.kill
    print "\r" + " " * 80 + "\r" # Clear the spinner line
  end
  
  puts "\n#{'!' * 80}".colorize(:red)
  puts "ERROR: Incomplete response from model after retries.".colorize(:red)
  puts "Missing fields:".colorize(:yellow)
  e.missing_fields.each do |field|
    puts "  - #{field}".colorize(:yellow)
  end
  
  if options[:debug] && e.partial_response
    puts "\nPartial response received:".colorize(:cyan)
    puts JSON.pretty_generate(e.partial_response).colorize(:cyan)
  end
  
  puts "\nTry increasing retries (-r option) or disabling strict mode (remove --strict)".colorize(:yellow)
  exit 1
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
  puts e.backtrace.join("\n") if options[:debug]
  exit 1
ensure
  # Always make sure the spinner thread is stopped
  if defined?(spinner_thread) && spinner_thread
    spinner_thread.kill rescue nil
  end
end
