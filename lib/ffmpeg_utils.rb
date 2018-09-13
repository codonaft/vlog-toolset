FFMPEG = 'ffmpeg -y -hide_banner -loglevel error'.freeze

def get_duration(filename)
  `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 #{filename}`.to_f
end

def take_first_channel(filename)
  output_filename = "#{filename}.1ch.wav"
  system "#{FFMPEG} -i #{filename} -af 'pan=mono|c0=c0' #{output_filename}"
  output_filename
end
