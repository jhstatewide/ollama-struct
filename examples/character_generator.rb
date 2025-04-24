#!/usr/bin/env ruby
# File: examples/character_generator.rb

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'ollama-struct', path: '.'
  gem 'optparse'
  gem 'terminal-table'
  gem 'colorize'
  gem 'tty-box'
  gem 'tty-progressbar'
end

options = {
  host: 'localhost',
  port: 11434,
  model: 'llama3.2',
  race: nil,
  class_type: nil,
  level: (1..20).to_a.sample,
  alignment: nil,
  genre: 'fantasy',
  retries: 2,
  temperature: 0.8,
  timeout: 120,
  themed: false
}

# Parse command line arguments
OptionParser.new do |opts|
  opts.banner = "Usage: character_generator.rb [options]"
  
  opts.separator ""
  opts.separator "Server options:"
  
  opts.on("--host HOST", "Ollama host (default: localhost)") do |h|
    options[:host] = h
  end
  
  opts.on("--port PORT", Integer, "Ollama port (default: 11434)") do |p|
    options[:port] = p
  end
  
  opts.on("-m", "--model MODEL", "Model to use (default: llama3.2)") do |m|
    options[:model] = m
  end
  
  opts.separator ""
  opts.separator "Character options:"
  
  opts.on("-r", "--race RACE", "Character race (e.g., Human, Elf, Dwarf)") do |r|
    options[:race] = r
  end
  
  opts.on("-c", "--class CLASS", "Character class (e.g., Warrior, Wizard, Rogue)") do |c|
    options[:class_type] = c
  end
  
  opts.on("-l", "--level LEVEL", Integer, "Character level (1-20, default: random)") do |l|
    options[:level] = [[l.to_i, 1].max, 20].min
  end
  
  opts.on("-a", "--alignment ALIGNMENT", "Character alignment (e.g., Lawful Good, Chaotic Neutral)") do |a|
    options[:alignment] = a
  end
  
  opts.on("-g", "--genre GENRE", "Setting genre (default: fantasy)") do |g|
    options[:genre] = g
  end
  
  opts.separator ""
  opts.separator "Generator options:"
  
  opts.on("--retries COUNT", Integer, "Number of retries for incomplete data (default: 2)") do |r|
    options[:retries] = r
  end
  
  opts.on("-t", "--temperature TEMP", Float, "Temperature for generation (default: 0.8)") do |t|
    options[:temperature] = t
  end
  
  opts.on("--timeout SECONDS", Integer, "Request timeout in seconds (default: 120)") do |t|
    options[:timeout] = t
  end
  
  opts.on("--themed", "Use themed terminal formatting") do
    options[:themed] = true
  end
  
  opts.on("--debug", "Enable debug output") do 
    options[:debug] = true
  end
end.parse!

# Create client instance with timeout
client = Ollama::Struct.new(
  model: options[:model],
  host: options[:host],
  port: options[:port],
  timeout: options[:timeout]
)

# Define a schema for character generation
character_schema = Ollama::Schema.object(
  properties: {
    basics: Ollama::Schema.object(
      properties: {
        name: Ollama::Schema.string,
        race: Ollama::Schema.string,
        class_type: Ollama::Schema.string,
        level: Ollama::Schema.integer,
        alignment: Ollama::Schema.string,
        background: Ollama::Schema.string,
        age: Ollama::Schema.integer,
        height: Ollama::Schema.string,
        weight: Ollama::Schema.string,
        appearance: Ollama::Schema.string,
        portrait_description: Ollama::Schema.string
      },
      required: %w[name race class_type level alignment background appearance]
    ),
    
    stats: Ollama::Schema.object(
      properties: {
        strength: Ollama::Schema.integer,
        dexterity: Ollama::Schema.integer,
        constitution: Ollama::Schema.integer,
        intelligence: Ollama::Schema.integer,
        wisdom: Ollama::Schema.integer,
        charisma: Ollama::Schema.integer,
        hit_points: Ollama::Schema.integer,
        armor_class: Ollama::Schema.integer,
        speed: Ollama::Schema.integer
      },
      required: %w[strength dexterity constitution intelligence wisdom charisma hit_points]
    ),
    
    abilities: Ollama::Schema.array(
      Ollama::Schema.object(
        properties: {
          name: Ollama::Schema.string,
          description: Ollama::Schema.string,
          effect: Ollama::Schema.string,
          usage: Ollama::Schema.string
        },
        required: %w[name description]
      ),
      min: 3,
      max: 8
    ),
    
    equipment: Ollama::Schema.object(
      properties: {
        weapons: Ollama::Schema.array(
          Ollama::Schema.object(
            properties: {
              name: Ollama::Schema.string,
              type: Ollama::Schema.string,
              damage: Ollama::Schema.string,
              properties: Ollama::Schema.string
            },
            required: %w[name type]
          ),
          min: 1,
          max: 3
        ),
        armor: Ollama::Schema.object(
          properties: {
            name: Ollama::Schema.string,
            type: Ollama::Schema.string,
            defense_bonus: Ollama::Schema.integer,
            properties: Ollama::Schema.string
          },
          required: %w[name type]
        ),
        items: Ollama::Schema.array(
          Ollama::Schema.object(
            properties: {
              name: Ollama::Schema.string,
              description: Ollama::Schema.string,
              quantity: Ollama::Schema.integer
            },
            required: %w[name]
          ),
          min: 3,
          max: 8
        )
      },
      required: %w[weapons armor items]
    ),
    
    story: Ollama::Schema.object(
      properties: {
        backstory: Ollama::Schema.string,
        motivation: Ollama::Schema.string,
        personality: Ollama::Schema.object(
          properties: {
            traits: Ollama::Schema.array(Ollama::Schema.string, min: 2, max: 4),
            ideals: Ollama::Schema.string,
            bonds: Ollama::Schema.string,
            flaws: Ollama::Schema.string
          },
          required: %w[traits]
        ),
        allies_and_enemies: Ollama::Schema.array(
          Ollama::Schema.object(
            properties: {
              name: Ollama::Schema.string,
              relationship: Ollama::Schema.string,
              description: Ollama::Schema.string
            },
            required: %w[name relationship]
          ),
          min: 1,
          max: 4
        ),
        quote: Ollama::Schema.string
      },
      required: %w[backstory motivation personality quote]
    )
  },
  required: %w[basics stats abilities equipment story]
)

# Prepare constraints for prompt
race_constraint = options[:race] ? "Race: #{options[:race]}" : "Choose an interesting fantasy race"
class_constraint = options[:class_type] ? "Class: #{options[:class_type]}" : "Choose an appropriate character class"
level_constraint = "Level: #{options[:level]}"
alignment_constraint = options[:alignment] ? "Alignment: #{options[:alignment]}" : "Choose a fitting alignment"
genre_constraint = options[:genre] || "fantasy"

# Prepare the prompt
prompt = <<~PROMPT
  Create a detailed #{genre_constraint} RPG character with the following characteristics:
  #{race_constraint}
  #{class_constraint}
  #{level_constraint}
  #{alignment_constraint}

  Include:
  1. Basic information (name, race, class, level, alignment, appearance)
  2. Character attributes/statistics (strength, intelligence, etc.)
  3. Special abilities and skills (at least 3)
  4. Equipment (weapons, armor, and other items)
  5. Detailed backstory, personality traits, motivations, and relationships
  
  Make this character unique, interesting, and fully fleshed out with a compelling story.
  Include specific stats that would be appropriate for this character's race and class.
PROMPT

messages = [{ role: 'user', content: prompt }]

# Show progress information
puts "\n#{'*' * 80}".colorize(options[:themed] ? :magenta : :bright_blue)
title = "🧙 Generating #{options[:race] || 'a'} #{options[:class_type] || 'fantasy'} character (Level #{options[:level]})"
puts title.center(80).colorize(options[:themed] ? :yellow : :bright_yellow)
puts "   Timeout: #{options[:timeout]} seconds (use --timeout to increase if needed)".colorize(:cyan) if options[:debug]
puts "#{'*' * 80}\n".colorize(options[:themed] ? :magenta : :bright_blue)

if options[:debug]
  puts "Using model: #{options[:model]} on #{options[:host]}:#{options[:port]}"
  puts "Temperature: #{options[:temperature]}, Retries: #{options[:retries]}"
  puts "-" * 80
end

progress = if options[:debug]
  nil
else
  bar = TTY::ProgressBar.new("[:bar] :percent", total: 100)
  6.times { bar.advance(Random.rand(4..10)); sleep 0.2 }
  bar
end

# Make the request
begin
  # Let the library handle validation and retries
  character = client.chat(
    messages: messages,
    format: character_schema,
    options: { 
      temperature: options[:temperature],
      max_retries: options[:retries],
      ensure_complete: true
    }
  )
  
  # Progress bar simulation
  unless options[:debug]
    12.times { progress.advance(Random.rand(3..6)); sleep 0.1 }
    progress.finish
  end
  
  # Extract data for display
  basics = character['basics']
  stats = character['stats']
  abilities = character['abilities']
  equipment = character['equipment']
  story = character['story']
  
  # Choose colors for themed mode
  theme = {
    title: options[:themed] ? :magenta : :bright_blue,
    header: options[:themed] ? :yellow : :bright_yellow,
    detail: options[:themed] ? :bright_cyan : :cyan,
    quote: options[:themed] ? :bright_green : :green,
    section: options[:themed] ? :magenta : :bright_blue,
    highlight: options[:themed] ? :bright_red : :red,
    text: options[:themed] ? :white : :white
  }
  
  # Display the character sheet
  puts "\n\n"
  title_box = TTY::Box.frame(
    width: 80,
    height: 3,
    align: :center,
    padding: 0,
    title: { top_left: '📜', top_right: '📜' },
    style: {
      fg: options[:themed] ? :yellow : :yellow,
      bg: options[:themed] ? :black : nil,
      border: { fg: options[:themed] ? :yellow : :bright_yellow }
    }
  ) { "#{basics['name']}".colorize(theme[:header]) }
  puts title_box
  
  # Display basic information
  puts "\n#{'=' * 80}".colorize(theme[:section])
  puts " BASIC INFORMATION".colorize(theme[:header])
  puts "#{'=' * 80}".colorize(theme[:section])
  
  basics_table = Terminal::Table.new do |t|
    t << ['Race', basics['race'].to_s.colorize(theme[:detail])]
    t << ['Class', basics['class_type'].to_s.colorize(theme[:detail])]
    t << ['Level', basics['level'].to_s.colorize(theme[:detail])]
    t << ['Alignment', basics['alignment'].to_s.colorize(theme[:detail])]
    t << ['Background', basics['background'].to_s.colorize(theme[:detail])] if basics['background']
    t << ['Age', basics['age'].to_s.colorize(theme[:detail])] if basics['age']
    t << ['Height', basics['height'].to_s.colorize(theme[:detail])] if basics['height']
    t << ['Weight', basics['weight'].to_s.colorize(theme[:detail])] if basics['weight']
    t.style = { border_x: '=', border_i: 'x' }
  end
  puts basics_table
  
  puts "\n#{'~' * 80}".colorize(theme[:detail])
  puts " 👤 APPEARANCE".colorize(theme[:header])
  puts "#{'~' * 80}".colorize(theme[:detail])
  puts basics['appearance'].to_s.colorize(theme[:text])
  puts "\n"
  puts basics['portrait_description'].to_s.colorize(theme[:text]) if basics['portrait_description']
  
  # Display statistics
  puts "\n#{'=' * 80}".colorize(theme[:section])
  puts " ATTRIBUTES & STATISTICS".colorize(theme[:header])
  puts "#{'=' * 80}".colorize(theme[:section])
  
  # Create a table with the main attributes
  stats_table = Terminal::Table.new do |t|
    t.add_row [
      {value: "STR", alignment: :center}, 
      {value: "DEX", alignment: :center}, 
      {value: "CON", alignment: :center}, 
      {value: "INT", alignment: :center}, 
      {value: "WIS", alignment: :center}, 
      {value: "CHA", alignment: :center}
    ]
    t.add_row [
      {value: stats['strength'].to_s.colorize(theme[:highlight]), alignment: :center}, 
      {value: stats['dexterity'].to_s.colorize(theme[:highlight]), alignment: :center}, 
      {value: stats['constitution'].to_s.colorize(theme[:highlight]), alignment: :center}, 
      {value: stats['intelligence'].to_s.colorize(theme[:highlight]), alignment: :center}, 
      {value: stats['wisdom'].to_s.colorize(theme[:highlight]), alignment: :center}, 
      {value: stats['charisma'].to_s.colorize(theme[:highlight]), alignment: :center}
    ]
    t.style = { border_x: '-', border_i: '+', alignment: :center }
  end
  puts stats_table
  
  # Display secondary stats
  secondary_stats = Terminal::Table.new do |t|
    t << ['Hit Points', stats['hit_points'].to_s.colorize(theme[:highlight])]
    t << ['Armor Class', stats['armor_class'].to_s.colorize(theme[:highlight])] if stats['armor_class']
    t << ['Speed', stats['speed'].to_s.colorize(theme[:highlight])] if stats['speed']
    t.style = { border_x: '-', border_i: '+' }
  end
  puts secondary_stats
  
  # Display abilities
  puts "\n#{'=' * 80}".colorize(theme[:section])
  puts " 🔮 ABILITIES & SPECIAL SKILLS".colorize(theme[:header])
  puts "#{'=' * 80}".colorize(theme[:section])
  
  abilities.each do |ability|
    puts "\n#{ability['name']}".colorize(theme[:highlight])
    puts "#{ability['description']}".colorize(theme[:text])
    puts "Effect: #{ability['effect']}".colorize(theme[:detail]) if ability['effect']
    puts "Usage: #{ability['usage']}".colorize(theme[:detail]) if ability['usage']
  end
  
  # Display equipment
  puts "\n#{'=' * 80}".colorize(theme[:section])
  puts " ⚔️ EQUIPMENT".colorize(theme[:header])
  puts "#{'=' * 80}".colorize(theme[:section])
  
  puts "\n🗡 Weapons:".colorize(theme[:detail])
  weapons_table = Terminal::Table.new do |t|
    t.headings = ['Name', 'Type', 'Damage', 'Properties']
    equipment['weapons'].each do |weapon|
      t.add_row [
        weapon['name'].to_s.colorize(theme[:highlight]),
        weapon['type'],
        weapon['damage'],
        weapon['properties']
      ]
    end
    t.style = { border_x: '-', border_i: '+' }
  end
  puts weapons_table
  
  puts "\n🛡 Armor:".colorize(theme[:detail])
  armor_table = Terminal::Table.new do |t|
    t.headings = ['Name', 'Type', 'Defense', 'Properties']
    t.add_row [
      equipment['armor']['name'].to_s.colorize(theme[:highlight]),
      equipment['armor']['type'],
      equipment['armor']['defense_bonus'],
      equipment['armor']['properties']
    ]
    t.style = { border_x: '-', border_i: '+' }
  end
  puts armor_table
  
  puts "\n🎒 Items:".colorize(theme[:detail])
  items_table = Terminal::Table.new do |t|
    t.headings = ['Name', 'Quantity', 'Description']
    equipment['items'].each do |item|
      t.add_row [
        item['name'].to_s.colorize(theme[:text]),
        item['quantity'] || 1,
        item['description']
      ]
    end
    t.style = { border_x: '-', border_i: '+' }
  end
  puts items_table
  
  # Display story elements
  puts "\n#{'=' * 80}".colorize(theme[:section])
  puts " 📖 STORY & BACKGROUND".colorize(theme[:header])
  puts "#{'=' * 80}".colorize(theme[:section])
  
  puts "\n📜 Backstory:".colorize(theme[:detail])
  puts "#{story['backstory']}".colorize(theme[:text])
  
  puts "\n🎯 Motivation:".colorize(theme[:detail])
  puts "#{story['motivation']}".colorize(theme[:text])
  
  puts "\n💭 Personality:".colorize(theme[:detail])
  personality_table = Terminal::Table.new do |t|
    t << ['Traits', story['personality']['traits'].join(', ').colorize(theme[:text])]
    t << ['Ideals', story['personality']['ideals'].to_s.colorize(theme[:text])] if story['personality']['ideals']
    t << ['Bonds', story['personality']['bonds'].to_s.colorize(theme[:text])] if story['personality']['bonds']
    t << ['Flaws', story['personality']['flaws'].to_s.colorize(theme[:text])] if story['personality']['flaws']
    t.style = { border_x: '-', border_i: '+' }
  end
  puts personality_table
  
  if story['allies_and_enemies'] && !story['allies_and_enemies'].empty?
    puts "\n👥 Relationships:".colorize(theme[:detail])
    story['allies_and_enemies'].each do |relationship|
      puts "- #{relationship['name']} (#{relationship['relationship']})".colorize(theme[:highlight])
      puts "  #{relationship['description']}".colorize(theme[:text]) if relationship['description']
    end
  end
  
  # Character quote
  puts "\n#{'~' * 80}".colorize(theme[:quote])
  quote_box = TTY::Box.frame(
    width: 80,
    padding: 1,
    align: :center,
    style: {
      fg: options[:themed] ? :green : :green,
      bg: options[:themed] ? :black : nil,
      border: { fg: options[:themed] ? :green : :green }
    }
  ) { "\"#{story['quote']}\"" }
  puts quote_box
  puts "#{'~' * 80}".colorize(theme[:quote])
  
rescue Ollama::TimeoutError => e
  # Clear the progress bar if it's displayed
  progress&.finish if progress
  
  puts "\n#{'!' * 80}".colorize(:red)
  puts "TIMEOUT ERROR: The request timed out after #{e.timeout_seconds} seconds.".colorize(:red)
  puts "\nSuggestions:".colorize(:yellow)
  puts "  1. Increase the timeout limit: --timeout #{e.timeout_seconds * 2}".colorize(:yellow)
  puts "  2. Try a simpler character (lower level or less complex class)".colorize(:yellow)
  puts "  3. Check if the Ollama server is under heavy load".colorize(:yellow)
  puts "  4. Try a different model that might be faster".colorize(:yellow)
  exit 1
rescue Ollama::IncompleteResponseError => e
  puts "\n#{'!' * 80}".colorize(:red)
  puts "ERROR: Failed to generate a complete character.".colorize(:red)
  puts "Missing fields:".colorize(:yellow)
  e.missing_fields.each do |field|
    puts "  - #{field}".colorize(:yellow)
  end
  
  if options[:debug] && e.partial_response
    puts "\nPartial response received:".colorize(:cyan)
    puts JSON.pretty_generate(e.partial_response).colorize(:cyan)
  end
  
  puts "\nTry increasing retries (--retries) or adjusting the temperature (-t)".colorize(:yellow)
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
end
