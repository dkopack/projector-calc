#!/usr/bin/env ruby

require 'optparse'
require 'json'

class ProjectorCalculator
  NITS_TO_FOOT_LAMBERTS = 0.292
  
  def initialize(projector_max_lumens, screen_diagonal, screen_gain = 1.0, aspect_ratio = 16.0/9.0, min_laser_output = 70.0)
    @projector_max_lumens = projector_max_lumens
    @screen_diagonal = screen_diagonal
    @screen_gain = screen_gain
    @aspect_ratio = aspect_ratio
    @min_laser_output = min_laser_output
    
    calculate_screen_dimensions
  end
  
  def calculate_screen_dimensions
    @screen_width = @screen_diagonal / Math.sqrt(1 + (1.0 / @aspect_ratio)**2)
    @screen_height = @screen_width / @aspect_ratio
    @screen_area_sq_inches = @screen_width * @screen_height
    @screen_area_sq_feet = @screen_area_sq_inches / 144.0
  end
  
  def lumens_needed_for_nits(target_nits)
    foot_lamberts = target_nits * NITS_TO_FOOT_LAMBERTS
    (foot_lamberts * @screen_area_sq_feet) / @screen_gain
  end
  
  def laser_power_for_nits(target_nits)
    lumens_needed = lumens_needed_for_nits(target_nits)
    actual_laser_percent = (lumens_needed / @projector_max_lumens.to_f) * 100
    
    if actual_laser_percent < @min_laser_output
      setting_value = 0
      actual_output = @min_laser_output
      actual_lumens = (@min_laser_output / 100.0) * @projector_max_lumens
    else
      setting_range = 100.0 - @min_laser_output
      actual_range = actual_laser_percent - @min_laser_output
      setting_value = (actual_range / setting_range) * 100
      actual_output = actual_laser_percent
      actual_lumens = (actual_laser_percent / 100.0) * @projector_max_lumens
    end
    
    actual_foot_lamberts = (actual_lumens * @screen_gain) / @screen_area_sq_feet
    actual_nits = actual_foot_lamberts / NITS_TO_FOOT_LAMBERTS
    actual_lux = actual_nits * Math::PI
    
    {
      target_nits: target_nits,
      lumens_needed: lumens_needed.round,
      actual_laser_percent: actual_output.round(1),
      setting_value: setting_value.round(1),
      actual_lumens: actual_lumens.round,
      actual_nits: actual_nits.round(1),
      actual_lux: actual_lux.round(1),
      achievable: actual_laser_percent <= 100
    }
  end
  
  def max_achievable_nits
    max_foot_lamberts = (@projector_max_lumens * @screen_gain) / @screen_area_sq_feet
    max_foot_lamberts / NITS_TO_FOOT_LAMBERTS
  end
  
  def screen_info
    {
      diagonal: @screen_diagonal,
      aspect_ratio: @aspect_ratio.round(2),
      width: @screen_width.round(1),
      height: @screen_height.round(1),
      area_sq_feet: @screen_area_sq_feet.round(2),
      gain: @screen_gain,
      projector_max_lumens: @projector_max_lumens,
      min_laser_output: @min_laser_output,
      max_achievable_nits: max_achievable_nits.round(1)
    }
  end
  
  def calculate_multiple_targets(targets)
    results = []
    
    targets.each do |target|
      result = laser_power_for_nits(target)
      results << result
    end
    
    results
  end
end

class CLI
  def initialize
    @options = {
      lumens: 1680,
      diagonal: 100,
      gain: 1.0,
      aspect_ratio: 16.0/9.0,
      min_laser: 70.0,
      format: 'table',
      interactive: false,
      info: false
    }
    
    @targets = []
  end
  
  def parse_options
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options] [target_nits...]"
      opts.separator ""
      opts.separator "Calculate projector laser power settings for target brightness levels"
      opts.separator ""
      opts.separator "Options:"
      
      opts.on("-l", "--lumens LUMENS", Integer, "Projector max lumens (default: 1680)") do |v|
        @options[:lumens] = v
      end
      
      opts.on("-d", "--diagonal DIAGONAL", Float, "Screen diagonal in inches (default: 100)") do |v|
        @options[:diagonal] = v
      end
      
      opts.on("-g", "--gain GAIN", Float, "Screen gain factor (default: 1.0)") do |v|
        @options[:gain] = v
      end
      
      opts.on("-a", "--aspect-ratio RATIO", Float, "Aspect ratio as decimal (default: 1.78 for 16:9)") do |v|
        @options[:aspect_ratio] = v
      end
      
      opts.on("-m", "--min-laser PERCENT", Float, "Minimum laser output at setting 0 (default: 70%)") do |v|
        @options[:min_laser] = v
      end
      
      opts.on("-f", "--format FORMAT", ['table', 'json', 'csv'], "Output format: table, json, csv (default: table)") do |v|
        @options[:format] = v
      end
      
      opts.on("-i", "--interactive", "Run in interactive mode") do
        @options[:interactive] = true
      end
      
      opts.on("--info", "Show screen information only") do
        @options[:info] = true
      end
      
      opts.on("--sdr [NITS]", Float, "Add SDR target (default: 55 nits)") do |v|
        @targets << (v || 55)
      end
      
      opts.on("--hdr [NITS]", Float, "Add HDR target (default: 150 nits)") do |v|
        @targets << (v || 150)
      end
      
      opts.on_tail("-h", "--help", "Show this help message") do
        puts opts
        exit
      end
      
      opts.on_tail("--version", "Show version") do
        puts "Projector Calculator v1.0"
        exit
      end
      
      opts.separator ""
      opts.separator "Examples:"
      opts.separator "  #{$0} 55 150                    # Calculate for 55 and 150 nits"
      opts.separator "  #{$0} --sdr --hdr               # Use default SDR (55) and HDR (150) values"
      opts.separator "  #{$0} --lumens 2000 --diagonal 100 --min-laser 60 120 200  # Custom setup"
      opts.separator "  #{$0} --interactive             # Interactive mode"
      opts.separator "  #{$0} --info                    # Show screen info only"
      opts.separator "  #{$0} --format json 55 150      # Output as JSON"
      opts.separator "  #{$0} --sdr 48 --hdr 200         # 48 nits SDR, 200 nits HDR"
    end
    
    begin
      parser.parse!
      
      ARGV.each do |arg|
        begin
          @targets << Float(arg)
        rescue ArgumentError
          STDERR.puts "Warning: Invalid target brightness '#{arg}' - skipping"
        end
      end
      
      if @targets.empty? && !@options[:interactive] && !@options[:info]
        @targets = [55, 150]
      end
      
    rescue OptionParser::InvalidOption, OptionParser::InvalidArgument => e
      STDERR.puts "Error: #{e}"
      STDERR.puts "Use --help for usage information"
      exit 1
    end
  end
  
  def run
    parse_options
    
    calculator = ProjectorCalculator.new(
      @options[:lumens],
      @options[:diagonal],
      @options[:gain],
      @options[:aspect_ratio],
      @options[:min_laser]
    )
    
    if @options[:info]
      show_screen_info(calculator)
    elsif @options[:interactive]
      interactive_mode(calculator)
    else
      calculate_targets(calculator)
    end
  end
  
  private
  
  def show_screen_info(calculator)
    info = calculator.screen_info
    
    case @options[:format]
    when 'json'
      puts JSON.pretty_generate(info)
    when 'csv'
      puts info.keys.join(',')
      puts info.values.join(',')
    else
      puts "Screen Information:"
      puts "==================="
      puts "Diagonal: #{info[:diagonal]}\" (#{info[:aspect_ratio]}:1 aspect ratio)"
      puts "Dimensions: #{info[:width]}\" x #{info[:height]}\""
      puts "Area: #{info[:area_sq_feet]} sq ft"
      puts "Gain: #{info[:gain]}x"
      puts "Projector max lumens: #{info[:projector_max_lumens]}"
      puts "Minimum laser output: #{info[:min_laser_output]}%"
      puts "Maximum achievable brightness: #{info[:max_achievable_nits]} nits"
    end
  end
  
  def calculate_targets(calculator)
    results = calculator.calculate_multiple_targets(@targets)
    
    case @options[:format]
    when 'json'
      output = {
        screen_info: calculator.screen_info,
        calculations: results
      }
      puts JSON.pretty_generate(output)
    when 'csv'
      puts "target_nits,lumens_needed,actual_laser_percent,setting_value,actual_lumens,actual_nits,actual_lux,achievable"
      results.each do |result|
        puts "#{result[:target_nits]},#{result[:lumens_needed]},#{result[:actual_laser_percent]},#{result[:setting_value]},#{result[:actual_lumens]},#{result[:actual_nits]},#{result[:actual_lux]},#{result[:achievable]}"
      end
    else
      show_screen_info(calculator) unless @targets.empty?
      puts
      puts "Laser Power Calculations:"
      puts "========================="
      
      results.each do |result|
        status = result[:achievable] ? "✓" : "⚠ NOT ACHIEVABLE"
        puts "#{result[:target_nits]} nits:"
        puts "  Lumens needed: #{result[:lumens_needed]}"
        puts "  Actual laser output: #{result[:actual_laser_percent]}%"
        puts "  Projector setting: #{result[:setting_value]} #{status}"
        puts "  Expected brightness: #{result[:actual_nits]} nits (#{result[:actual_lux]} lux)"
        puts
      end
      
      unachievable = results.reject { |r| r[:achievable] }
      unless unachievable.empty?
        puts "Warnings:"
        puts "========="
        max_nits = calculator.max_achievable_nits
        unachievable.each do |result|
          puts "#{result[:target_nits]} nits exceeds projector capability."
          puts "  Maximum achievable: #{max_nits.round(1)} nits at 100% laser power"
        end
      end
    end
  end
  
  def interactive_mode(calculator)
    puts "Projector Calculator - Interactive Mode"
    puts "======================================="
    show_screen_info(calculator)
    puts
    puts "Enter target brightness in nits (or 'quit' to exit):"
    
    loop do
      print "> "
      input = gets.chomp
      
      break if input.downcase == 'quit'
      
      begin
        target_nits = Float(input)
        result = calculator.laser_power_for_nits(target_nits)
        
        puts "Target: #{target_nits} nits"
        puts "Lumens needed: #{result[:lumens_needed]}"
        puts "Actual laser output: #{result[:actual_laser_percent]}%"
        puts "Projector setting: #{result[:setting_value]}"
        puts "Expected brightness: #{result[:actual_nits]} nits (#{result[:actual_lux]} lux)"
        puts "Achievable: #{result[:achievable] ? 'Yes' : 'No'}"
        puts
      rescue ArgumentError
        puts "Please enter a valid number or 'quit'"
      end
    end
  end
end

if __FILE__ == $0
  CLI.new.run
end