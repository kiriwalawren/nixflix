{
  config,
  pkgs,
  lib,
  ...
}:
with lib; {
  options.nixflix.jellyfin.encoding = {
    enableHardwareEncoding = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to do Hardware Acceleration";
    };

    allowHevcEncoding = mkOption {
      type = types.bool;
      default = false;
      description = "Whether HEVC encoding is enabled";
    };

    allowAv1Encoding = mkOption {
      type = types.bool;
      default = false;
      description = "Whether AV1 encoding is enabled";
    };

    encodingThreadCount = mkOption {
      type = types.int;
      default = -1;
      description = ''
        Amount of threads used for encoding.

        Set to -1 for automatic and 0 for max.
      '';
    };

    transcodingTempPath = mkOption {
      type = types.str;
      default = "${config.nixflix.jellyfin.cacheDir}/transcodes";
      defaultText = literalExpression ''"''${config.nixflix.jellyfin.cacheDir}/transcodes"'';
      description = "Path for temporary transcoded files when streaming";
    };

    enableFallbackFont = mkEnableOption "Enable fallback font";

    fallbackFontPath = mkOption {
      type = types.str;
      default = "";
      description = "Path to fallback font file for subtitle burning";
    };

    enableAudioVbr = mkEnableOption "Enable VBR Audio";

    downMixAudioBoost = mkOption {
      type = types.number;
      default = 2;
      description = "Boost audio when downmixing. A value of one will preserve the original volume.";
    };

    downMixStereoAlgorithm = mkOption {
      type = types.enum [
        "None"
        "Dave750"
        "NightmodeDialogue"
        "RFC7845"
        "AC-4"
      ];
      default = "None";
      description = "Algorithm used to downmix multi-channel audio to stereo.";
    };

    maxMuxingQueueSize = mkOption {
      type = types.int;
      default = 2048;
      description = ''
        Maximum number of packets that can be buffered while waiting for all streams to initialize.
        Try to increase it if you still meet "Too many packets buffered for output stream" error in FFmpeg logs.

        The recommended value is `2048`.
      '';
    };

    enableThrottling = mkEnableOption ''
      When a transcode or remux gets far enough ahead from the current playback position, pause the process so it will consume fewer resources.
      This is most useful when watching without seeking often. Turn this off if you experience playback issues.
    '';

    throttleDelaySeconds = mkOption {
      type = types.int;
      default = 180;
      description = ''
        Time in seconds after which the transcoder will be throttled.
        Must be large enough for the client to maintain a healthy buffer.
        Only works if throttling is enabled.
      '';
    };

    enableSegmentDeletion = mkEnableOption ''
      Delete old segments after they have been downloaded by the client.
      This prevents having to store the entire transcoded file on disk.
      Turn this off if you experience playback issues.
    '';

    segmentKeepSeconds = mkOption {
      type = types.int;
      default = 720;
      description = ''
        Time in seconds for which segments should be kept after they are downloaded by the client.
        Only works if segment deletion is enabled.
      '';
    };

    hardwareAccelerationType = mkOption {
      type = types.enum [
        "none"
        "qsv"
        "amf"
        "nvenc"
        "vaapi"
        "rkmpp"
        "videotoolbox"
        "v4l2m2m"
      ];
      description = ''
        Whether or not to use hardware acceleration for transcoding.

        If you misconfigure this your streams **will not work**!.
        More info: https://jellyfin.org/docs/general/administration/hardware-acceleration/
      '';
      default = "none";
    };

    encoderAppPathDisplay = mkOption {
      type = types.str;
      description = "The path to the FFmpeg application file or folder containing FFmpeg.";
      default = "${pkgs.jellyfin-ffmpeg}/bin/ffmpeg";
      defaultText = literalExpression ''"$${pkgs.jellyfin-ffmpeg}/bin/ffmpeg"'';
    };

    vaapiDevice = mkOption {
      type = types.str;
      description = ''
        This is the render node that is used for hardware acceleration.
        Only used if `HardwareAccelerationType` is set to `vaapi`.
      '';
      default = "/dev/dri/renderD128";
    };

    qsvDevice = mkOption {
      type = types.str;
      description = ''
        Specify the device for Intel QSV on a multi-GPU system.
        On Linux, this is the render node, e.g., /dev/dri/renderD128.
        Leave blank unless you know what you are doing.
      '';
      default = "";
    };

    # Tonemapping
    enableTonemapping = mkEnableOption ''
      Tone-mapping can transform the dynamic range of a video from HDR to SDR while maintaining image details and colors, which are very important information for representing the original scene.
      Currently works only with 10bit HDR10, HLG and DoVi videos. This requires the corresponding GPGPU runtime.
    '';

    tonemappingAlgorithm = mkOption {
      type = types.enum [
        "none"
        "bt2390"
        "clip"
        "linear"
        "gamma"
        "reinhard"
        "hable"
        "mobius"
      ];
      description = ''
        Tone mapping can be fine-tuned.
        If you are not familiar with these options, just keep the default.
      '';
      default = "bt2390";
    };

    tonemappingMode = mkOption {
      type = types.enum [
        "auto"
        "max"
        "rgb"
        "lum"
        "itp"
      ];
      description = ''
        Select the tone mapping mode.
        If you experience blown out highlights try switching to the RGB mode.
      '';
      default = "auto";
    };

    tonemappingRange = mkOption {
      type = types.enum [
        "auto"
        "tv"
        "pc"
      ];
      description = ''
        Select the output color range. Auto is the same as the input range.
      '';
      default = "auto";
    };

    tonemappingDesat = mkOption {
      type = types.number;
      description = ''
        Apply desaturation for highlights that exceed this level of brightness.
        The higher the parameter, the more color information will be preserved.
        This setting helps prevent unnaturally blown-out colors for super-highlights, by (smoothly) turning into white instead.
        This makes images feel more natural, at the cost of reducing information about out-of-range colors.

        The recommended and default values are 0 and 0.5.
      '';
      default = 0;
    };

    tonemappingPeak = mkOption {
      type = types.number;
      description = ''
        Override signal/nominal/reference peak with this value.
        Useful when the embedded peak information in display metadata is not reliable or when tone mapping from a lower range to a higher range.

        The recommended and default values are 100 and 0.
      '';
      default = 100;
    };

    tonemappingParam = mkOption {
      type = types.number;
      description = ''
        Tune the tone mapping algorithm.
        The recommended and default values are 0.

        Recommended to leave unchanged
      '';
      default = 0;
    };

    enableVppTonemapping = mkEnableOption ''
      Full Intel driver based tone-mapping. Currently works only on certain hardware with HDR10 videos. This has a higher priority compared to another OpenCL implementation.
    '';

    enableVideoToolboxTonemapping = mkEnableOption ''
      Apple VideoToolbox based tone-mapping. Works only on macOS with supported hardware.
    '';

    vppTonemappingBrightness = mkOption {
      type = types.number;
      description = ''
        Apply brightness gain in VPP tone mapping.

        The recommended and default values are 16 and 0.
      '';
      default = 16;
    };

    vppTonemappingContrast = mkOption {
      type = types.number;
      description = ''
        Apply contrast gain in VPP tone mapping.

        Both recommended and default values are 1.
      '';
      default = 1;
    };

    h264Crf = mkOption {
      type = types.int;
      description = ''
        The 'Constant Rate Factor' (CRF) is the default quality setting for the x264 and x265 software encoders.
        You can set the values between 0 and 51, where lower values would result in better quality (at the expense of higher file sizes).
        Sane values are between 18 and 28.

        Hardware encoders do not use these settings.
      '';
      default = 23;
    };

    h265Crf = mkOption {
      type = types.int;
      description = ''
        The 'Constant Rate Factor' (CRF) is the default quality setting for the x264 and x265 software encoders.
        You can set the values between 0 and 51, where lower values would result in better quality (at the expense of higher file sizes).
        Sane values are between 18 and 28.

        Hardware encoders do not use these settings.
      '';
      default = 28;
    };

    encoderPreset = mkOption {
      type = types.enum [
        "auto"
        "veryslow"
        "slower"
        "slow"
        "medium"
        "fast"
        "faster"
        "veryfast"
        "superfast"
        "ultrafast"
      ];
      default = "auto";
      description = ''
        Pick a faster value to improve performance, or a slower value to improve quality.
      '';
    };

    deinterlaceDoubleRate = mkEnableOption ''
      This setting uses the field rate when deinterlacing, often referred to as bob deinterlacing, which doubles the frame rate of the video to provide full motion like what you would see when viewing interlaced video on a TV.
    '';

    deinterlaceMethod = mkOption {
      type = types.enum [
        "yadif"
        "bwdif"
      ];
      default = "yadif";
      description = ''
        Select the deinterlacing method to use when software transcoding interlaced content.
        When hardware acceleration supporting hardware deinterlacing is enabled the hardware deinterlacer will be used instead of this setting.
      '';
    };

    enableDecodingColorDepth10Hevc = mkOption {
      type = types.bool;
      default = true;
      description = "Enable hardware decoding for HEVC 10bit";
    };

    enableDecodingColorDepth10Vp9 = mkOption {
      type = types.bool;
      default = true;
      description = "Enable hardware decoding for VP9 10bit";
    };

    enableDecodingColorDepth10HevcRext = mkEnableOption "Enable hardware decoding for HEVC RExt 8/10bit";

    enableDecodingColorDepth12HevcRext = mkEnableOption "Enable hardware decoding for HEVC RExt 12bit";

    enableEnhancedNvdecDecoder = mkOption {
      type = types.bool;
      default = true;
      description = "Enable enhanced NVDEC decoder. Requires Nvidia GPU with enhanced NVDEC support.";
    };

    preferSystemNativeHwDecoder = mkOption {
      type = types.bool;
      default = true;
      description = "Prefer system native hardware decoder over FFmpeg implementations.";
    };

    hardwareDecodingCodecs = mkOption {
      type = types.listOf (
        types.enum [
          "h264"
          "hevc"
          "mpeg2video"
          "vc1"
          "vp8"
          "vp9"
          "av1"
        ]
      );
      default = [
        "h264"
        "hevc"
        "mpeg2video"
        "vc1"
      ];
      description = ''
        List of codec types to enable hardware decoding for.
        Should only include codecs your hardware has support for.

        Consult https://jellyfin.org/docs/general/administration/hardware-acceleration/ for more info.
      '';
    };

    enableIntelLowPowerH264HwEncoder = mkEnableOption ''
      Low-Power Encoding can keep unnecessary CPU-GPU sync. On Linux they must be disabled if the i915 HuC firmware is not configured.

      https://jellyfin.org/docs/general/administration/hardware-acceleration/intel/#configure-and-verify-lp-mode-on-linux
    '';

    enableIntelLowPowerHevcHwEncoder = mkEnableOption ''
      Low-Power Encoding can keep unnecessary CPU-GPU sync. On Linux they must be disabled if the i915 HuC firmware is not configured.

      https://jellyfin.org/docs/general/administration/hardware-acceleration/intel/#configure-and-verify-lp-mode-on-linux
    '';

    enableSubtitleExtraction = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Embedded subtitles can be extracted from videos and delivered to clients in plain text, in order to help prevent video transcoding.
        On some systems this can take a long time and cause video playback to stall during the extraction process.
        Disable this to have embedded subtitles burned in with video transcoding when they are not natively supported by the client device.
      '';
    };

    allowOnDemandMetadataBasedKeyframeExtractionForExtensions = mkOption {
      type = with types; listOf str;
      description = "imma be real i have no idea what this option is. Just leave it as the default";
      default = ["mkv"];
    };
  };
}
