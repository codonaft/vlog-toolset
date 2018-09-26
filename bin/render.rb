#!/bin/env ruby

require 'ffmpeg_utils.rb'
require 'concurrent'
require 'fileutils'
require 'io/console'
require 'optparse'
require 'thread/pool'

PREVIEW_WIDTH = 320

def parse(filename)
  File.open filename do |f|
    f.map { |line| line.split("\t") }
     .map
     .with_index do |cols, index|
      if cols[0] == "\n" then { index: index, empty: true }
      else
        video_filename, speed, start_position, end_position = cols
        {
          index: index,
          video_filename: video_filename,
          speed: speed.to_f,
          start_position: start_position.to_f,
          end_position: end_position.to_f,
          empty: false
        }
      end
    end
  end
end

def apply_delays(segments)
  print "computing delays\n"

  delay_time = 1.0

  start_correction = 0.3
  end_correction = 0.3

  video_durations = {}

  segments
    .reverse
    .inject([0, []]) do |(delays, acc), seg|
      if seg[:empty] then [delays + 1, acc]
      else [0, acc + [[seg, delays]]] end
    end[1]
    .reverse
    .reject { |(seg, _delays)| seg[:empty] }
    .map do |(seg, delays)|
    if video_durations[seg[:video_filename]].nil?
      video_durations[seg[:video_filename]] = get_duration seg[:video_filename]
    end
    duration = video_durations[seg[:video_filename]]

    new_start_position = [seg[:start_position] - start_correction, 0.0].max
    new_end_position = [seg[:end_position] + delays * delay_time + end_correction, duration].min
    seg.merge(start_position: new_start_position)
    seg.merge(end_position: new_end_position)
  end
end

def in_segment?(position, segment)
  (segment[:start_position]..segment[:end_position]).cover? position
end

def segments_overlap?(a, b)
  in_segment?(a[:start_position], b) || in_segment?(a[:end_position], b)
end

def merge_small_pauses(segments, min_pause_between_shots)
  segments.inject([]) do |acc, seg|
    if acc.empty?
      acc.append(seg.clone)
    else
      prev = acc.last
      dt = seg[:start_position] - prev[:end_position]
      has_overlap = segments_overlap?(seg, prev)
      is_successor = (seg[:video_filename] == prev[:video_filename]) && (dt < min_pause_between_shots || has_overlap)
      if is_successor
        prev[:start_position] = [seg[:start_position], prev[:start_position]].min
        prev[:start_position] = 0.0 if prev[:start_position] < 0.2
        prev[:end_position] = [seg[:end_position], prev[:end_position]].max
        prev[:speed] = [seg[:speed], prev[:speed]].max
      else
        acc.append(seg.clone)
      end
      acc
    end
  end
end

def process_and_split_videos(segments, options, temp_dir)
  print "processing video clips\n"

  fps = options[:fps]
  preview = options[:preview]
  speed = options[:speed]

  thread_pool = Concurrent::FixedThreadPool.new(Concurrent.processor_count)

  temp_videos = segments.map do |seg|
    segment_speed = clamp_speed(seg[:speed] * speed)

    ext = '.mp4'
    basename = File.basename seg[:video_filename]
    filename = File.join temp_dir, "#{basename}#{ext}_#{segment_speed}_#{preview}_#{seg[:start_position]}_#{seg[:end_position]}"
    temp_video_filename = "#{filename}#{ext}"
    temp_cut_video_filename = "#{filename}.cut#{ext}"

    thread_pool.post do
      audio_filters = "atempo=#{segment_speed}"
      video_filters = "#{options[:video_filters]}, fps=#{fps}, setpts=(1/#{segment_speed})*PTS"
      if preview
        video_filters = "scale=#{PREVIEW_WIDTH}:-1, #{video_filters}, drawtext=fontcolor=white:x=#{PREVIEW_WIDTH / 3}:text=#{basename} #{seg[:index] + 1}"
      end

      video_codec = 'libx264 -preset ultrafast -crf 18'

      command = "#{FFMPEG_NO_OVERWRITE} -threads 1 \
                           -ss #{seg[:start_position]} \
                           -i #{seg[:video_filename]} \
                           -to #{seg[:end_position] - seg[:start_position]} \
                           -c copy #{temp_cut_video_filename} && \
                 #{FFMPEG_NO_OVERWRITE} -threads 1 \
                           -i #{temp_cut_video_filename} \
                           -vcodec #{video_codec} \
                           -vf '#{video_filters}' \
                           -af '#{audio_filters}' \
                           -acodec alac \
                           -f ipod #{temp_video_filename}"

      system command
      FileUtils.rm_f temp_cut_video_filename
    end

    temp_video_filename
  end

  thread_pool.shutdown
  thread_pool.wait_for_termination

  temp_videos
end

def concat_videos(temp_videos, output_filename)
  print "rendering to #{output_filename}\n"

  parts = temp_videos.map { |f| "file '#{f}'" }
                     .join "\n"

  command = "#{FFMPEG} -f concat -safe 0 -protocol_whitelist file,pipe -i - -vcodec copy -acodec alac -f ipod #{output_filename}"

  IO.popen(command, 'w') do |f|
    f.puts parts
    f.close_write
  end

  print "done\n"
end

def compute_player_position(segments, options)
  segments.select { |seg| seg[:index] < options[:line_in_file] - 1 }
          .map { |seg| seg[:end_position] - seg[:start_position] }
          .sum / clamp_speed(options[:speed])
end

def test_segments_overlap
  raise unless segments_overlap?({ start_position: 0.0, end_position: 5.0 }, start_position: 4.0, end_position: 6.0)
  raise unless segments_overlap?({ start_position: 0.0, end_position: 5.0 }, start_position: 5.0, end_position: 6.0)
  raise if segments_overlap?({ start_position: 0.0, end_position: 5.0 }, start_position: 6.0, end_position: 7.0)

  raise unless segments_overlap?({ start_position: 4.0, end_position: 6.0 }, start_position: 0.0, end_position: 5.0)
  raise unless segments_overlap?({ start_position: 5.0, end_position: 6.0 }, start_position: 0.0, end_position: 5.0)
  raise if segments_overlap?({ start_position: 6.0, end_position: 7.0 }, start_position: 0.0, end_position: 5.0)
end

def test_merge_small_pauses
  min_pause_between_shots = 2.0

  segments = [
    { index: 0, video_filename: 'a.mp4', start_position: 0.0, end_position: 5.0, speed: 1.0 },
    { index: 1, video_filename: 'a.mp4', start_position: 5.5, end_position: 10.0, speed: 1.5 },
    { index: 2, video_filename: 'b.mp4', start_position: 1.0, end_position: 3.0, speed: 1.0 },
    { index: 3, video_filename: 'b.mp4', start_position: 10.0, end_position: 20.0, speed: 1.0 },
    { index: 3, video_filename: 'b.mp4', start_position: 19.0, end_position: 22.0, speed: 1.8 },
    { index: 4, video_filename: 'b.mp4', start_position: 6.0, end_position: 8.0, speed: 1.0 },
    { index: 4, video_filename: 'b.mp4', start_position: 3.0, end_position: 7.0, speed: 1.0 }
  ]

  expected = [
    { index: 0, video_filename: 'a.mp4', start_position: 0.0, end_position: 10.0, speed: 1.5 },
    { index: 2, video_filename: 'b.mp4', start_position: 1.0, end_position: 3.0, speed: 1.0 },
    { index: 3, video_filename: 'b.mp4', start_position: 3.0, end_position: 22.0, speed: 1.8 }
  ]

  result = merge_small_pauses(segments, min_pause_between_shots)
  raise unless result == expected
end

def parse_options!(options)
  OptionParser.new do |opts|
    opts.banner = 'Usage: vlog-recorder.rb -p project_dir/ [other options]'
    opts.on('-p', '--project [dir]', 'Project directory') { |p| options[:project_dir] = p }
    opts.on('-L', '--line [num]', 'Line in video.meta file, to play by given position (default: 1)') { |l| options[:line_in_file] = l }
    opts.on('-P', '--preview [true|false]', 'Preview mode (default: true)') { |p| options[:preview] = p == 'true' }
    opts.on('-f', '--fps [num]', 'Constant frame rate (default: 30)') { |f| options[:fps] = f.to_i }
    opts.on('-S', '--speed [num]', 'Speed factor (default: 1.2)') { |s| options[:speed] = s.to_f }
    opts.on('-V', '--video-filters [filters]', 'ffmpeg video filters (default: "atadenoise,hflip,vignette")') { |v| options[:video_filters] = v }
  end.parse!

  raise OptionParser::MissingArgument if options[:project_dir].nil?
end

test_merge_small_pauses
test_segments_overlap

options = {
  fps: 30,
  speed: 1.2,
  video_filters: 'atadenoise,hflip,vignette',
  min_pause_between_shots: 0.1,
  preview: true,
  line_in_file: 1
}

parse_options!(options)

project_dir = options[:project_dir]
metadata_filename = File.join project_dir, 'videos.meta'
output_filename = File.join project_dir, 'output.mp4'

Dir.chdir project_dir

min_pause_between_shots = 0.1
segments = merge_small_pauses apply_delays(parse(metadata_filename)), min_pause_between_shots

temp_dir = File.join project_dir, 'tmp'
FileUtils.mkdir_p(temp_dir)

temp_videos = process_and_split_videos segments, options, temp_dir
concat_videos temp_videos, output_filename

player_position = compute_player_position segments, options
print "player_position = #{player_position}\n"
system "mpv --really-quiet --start=#{player_position} #{output_filename}"
