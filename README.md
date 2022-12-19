# encodeformastodon

Simple command-line tool for macOS that encodes videos in a format suitable for publishing to Mastodon.

I wrote this tool because upon uploading a vertical video to my Mastodon account, I noticed that they didn't convert the video properly, resulting in a distorted video.
This tool is a temporary workaround until Mastodon gets better support for video uploads.

All it does is resize the video to fit in a 1920x1080 resolution, pillar-boxing if needed.

```
OVERVIEW: Encodes and resizes any input video in a format suitable for
publishing to Mastodon.

USAGE: encodeformastodon <path>

ARGUMENTS:
  <path>                  Path to the video file that will be encoded

OPTIONS:
  -h, --help              Show help information.
```

You can see a before/after example in the image below:

![example](./example.png)