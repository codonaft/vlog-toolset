#!/bin/env ruby

require 'phone.rb'
require 'microphone.rb'

require 'concurrent'
require 'fileutils'
require 'io/console'
require 'logger'

class DevicesFacade
  def initialize(project_dir, temp_dir, arecord_args, logger)
    @project_dir = project_dir
    @temp_dir = temp_dir
    @logger = logger

    @recording = false
    @clip_num = get_last_clip_num
    @logger.debug "clip_num is #{@clip_num}"

    @microphone = Microphone.new(temp_dir, arecord_args, logger)

    @phone = Phone.new(temp_dir, logger)
    @phone.set_brightness(0)

    @thread_pool = Concurrent::FixedThreadPool.new(Concurrent.processor_count)

    logger.info('initialized')
  end

  def get_last_clip_num
    Dir.glob("{#{@temp_dir},#{@project_dir}}#{File::SEPARATOR}*.{wav,mp4}")
       .map { |f| f.gsub(/.*#{File::SEPARATOR}0*/, '').gsub(/\..*$/, '').to_i }.max || 0
  end

  def start_recording
    @logger.debug 'start recording'
    toggle_recording unless @recording
  end

  def stop_recording
    @logger.debug 'stop recording'
    toggle_recording if @recording
  end

  def toggle_recording
    @recording = !@recording
    @clip_num += 1 if @recording

    @phone.toggle_recording
    @microphone.toggle_recording @clip_num
  end

  def focus
    @logger.debug 'focus'
    @phone.focus
  end

  def delete_clip
    @microphone.delete_clip
    @phone.delete_clip
  end

  def save_clip
    # output_filename = File.join @project_dir, '%016d.mkv' % @clip_num
    #
    # @logger.debug("saving #{output_filename}")
    # clip_filename = @phone.clip_filename
    # sound_filename = @microphone.sound_filename
    #
    # @thread_pool.post do
    #   begin
    #     @phone.move_clip_to(clip_filename)
    #     processed_sound_filename = process_sound(sound_filename, clip_filename) # sync + convert to flac
    #     system("ffmpeg -i #{clip_filename} -i #{processed_sound_filename} -codec copy #{output_filename}")
    #     FileUtils::rm_f([clip_filename, sound_filename, processed_sound_filename])
    #     @logger.info("saved #{output_filename}")
    #   rescue StandardError => error
    #     @logger.error("failed to save #{output_filename}")
    #     @logger.error error
    #   end
    # end
  end

  def close
    stop_recording
    save_clip

    @phone.restore_brightness
    @phone.close_opencamera

    @thread_pool.shutdown
    @thread_pool.wait_for_termination
  end

  def show_status
    size = 10
    text = @recording ? 'LIVE' : 'stopped'
    postfix = ' ' * (size - text.length)
    print "[ #{text} ]#{postfix}\r"
    STDOUT.flush
  end
end

def show_help
  puts 'r - (RE)START recording'
  puts 's - STOP and SAVE current clip'
  puts 'd - STOP and DELETE current clip'
  puts 'f - FOCUS camera on center'
  puts 'h — show HELP'
  puts 'q / Ctrl+C - QUIT'
  puts
end

def run_main_loop(devices)
  loop do
    devices.show_status

    case STDIN.getch
    when 'q'
      print "Quit? y/n\r"
      break if STDIN.getch == 'y'
    when 'r'
      devices.stop_recording
      devices.show_status
      devices.delete_clip
      devices.start_recording
    when 's'
      devices.stop_recording
      devices.save_clip
    when 'd'
      devices.stop_recording
      devices.delete_clip
    when 'f'
      devices.focus
    when 'h'
      show_help
    end
  end
end

if ARGV.empty?
  puts 'syntax phone-and-mic-rec.rb project_dir/ [arecord-args]'
  exit 1
end

begin
  project_dir = ARGV[0]
  temp_dir = File.join project_dir, 'tmp'
  FileUtils.mkdir_p(temp_dir)

  arecord_args = ARGV[1].nil? ? 'default' : ARGV[1]

  logger = Logger.new(File.join(project_dir, 'log.txt'))
  # logger.level = Logger::WARN

  devices = DevicesFacade.new project_dir, temp_dir, arecord_args, logger
  show_help
  run_main_loop(devices)
rescue SystemExit, Interrupt
rescue StandardError => error
  logger.fatal(error) unless logger.nil?
  puts error
ensure
  puts 'Exiting...'
  logger.info('exit') unless logger.nil?

  devices.close unless devices.nil?
  logger.close unless logger.nil?
end
