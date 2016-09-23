{ config, pkgs, lib, hclib, ... }:

let
  inherit (lib) mkOption types;

  cfg = config.headcounter.services.postfix;

  postfix = pkgs.callPackage ./postpatch.nix { postfix = cfg.package; };

  optDoc = opt: "<option>headcounter.services.postfix.${opt}</option>";

  portType = lib.mkOptionType {
    name = "TCP port";
    check = p: lib.isInt p && p <= 65535 && p >= 0;
    merge = lib.mergeOneOption;
  };

  serviceOptions = { name, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = ''
          The name of the service to run.
        '';
      };

      type = mkOption {
        type = types.enum [ "inet" "unix" "fifo" "pass" ];
        default = "unix";
        description = ''
          The type of the service, one of the following:

          ${hclib.enumDoc {
            inet = "The service listens on a TCP/IP socket and is"
                 + " accessible via the network.";
            unix = "The service listens on a UNIX-domain socket and is"
                 + " accessible for local clients only.";
            fifo = "The service listens on a FIFO (named pipe) and is"
                 + " accessible for local clients only.";
            pass = "The service listens on a UNIX-domain socket, and is"
                 + " accessible to local clients only. It receives one"
                 + " open connection per connection request.";
          }}
        '';
      };

      address = mkOption {
        type = types.either portType types.str;
        default = name;
        example = "[::1]:25";
        description = ''
          If the service <option>type</option> is inet, it is a colon-separated
          pair of the hostname to bind to and the port.

          Otherwise the value is a path relative to ${optDoc "queueDir"}.
        '';
      };

      private = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether the service's sockets and storage directory is restricted to
          be only available via the mail system.
        '';
      };

      capabilities = mkOption {
        type = types.listOf (types.enum [
          "AUDIT_CONTROL" "AUDIT_READ" "AUDIT_WRITE" "BLOCK_SUSPEND" "CHOWN"
          "DAC_OVERRIDE" "DAC_READ_SEARCH" "FOWNER" "FSETID" "IPC_LOCK"
          "IPC_OWNER" "KILL" "LEASE" "LINUX_IMMUTABLE" "MAC_ADMIN"
          "MAC_OVERRIDE" "MKNOD" "NET_ADMIN" "NET_BIND_SERVICE" "NET_BROADCAST"
          "NET_RAW" "SETFCAP" "SETGID" "SETPCAP" "SETUID" "SYSLOG" "SYS_ADMIN"
          "SYS_BOOT" "SYS_CHROOT" "SYS_MODULE" "SYS_NICE" "SYS_PACCT"
          "SYS_PTRACE" "SYS_RAWIO" "SYS_RESOURCE" "SYS_TIME" "SYS_TTY_CONFIG"
          "WAKE_ALARM"
        ]);
        default = [];
        description = ''
          The capability bounding set this service gets assigned, see
          <citerefentry>
            <refentrytitle>capabilities</refentrytitle>
            <manvolnum>7</manvolnum>
          </citerefentry>
          for details.

          This deviates from the upstream Postfix master process configuration
          where there is only a flag whether the process is privileged or not.

          Postfix either runs the process as root or as the postfix users
          whether the flag is set or not set, using capabilities allows us to
          have a more fine-grained control about what a particular service is
          allowed to regardless of the user account it's running as.
        '';
      };

      chroot = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether the service is chrooted to have only access to the
          ${optDoc "queueDir"} and the closure of store paths specified by the
          <option>program</option> option.
        '';
      };

      wakeup = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = ''
          Automatically wake up the service after the specified number of
          seconds.
        '';
      };

      wakeupOnUse = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether no wake up events should be sent before the first time this
          service is used.
        '';
      };

      processLimit = mkOption {
        type = types.int;
        default = cfg.defaultProcessLimit;
        apply = x: if x == 0 then 4294967295 else x;
        description = ''
          The maximum number of processes to spawn for this service, by default
          it's the value set by ${optDoc "defaultProcessLimit"}. If the value
          is <literal>0</literal> it doesn't have any limit.
        '';
      };

      program = mkOption {
        type = lib.mkOptionType {
          name = "Postfix program or path to program in the Nix store";
          check = x: lib.hasPrefix builtins.storeDir x
                  || lib.replaceStrings ["/"] ["X"] x == x;
          merge = lib.mergeOneOption;
        };
        default = name;
        example = "smtp";
        description = ''
          Either a single program name specifying a Postfix service/daemon
          process or a valid store path to the full binary to execute.
        '';
      };

      args = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "-o" "smtp_helo_timeout=5" ];
        description = ''
          Arguments to pass to the <option>program</option>. There is no shell
          processing involved and shell syntax is passed verbatim to the
          process.
        '';
      };

      verbose = mkOption {
        type = types.bool;
        default = false;
        description = "Make the service more verbose.";
      };

      debug = mkOption {
        type = types.bool;
        default = false;
        description = "Enable debugging output for this service.";
      };
    };
  };

  mkPrefixedUnits = generator: let
    mkUnit = name: attrs: let
      fullName = "postfix.${name}";
    in lib.nameValuePair fullName (generator attrs);
  in lib.mapAttrs' mkUnit;

  cfgfile = let
    escape = lib.replaceStrings ["$"] ["$$"];
    mkList = items: "\n" + lib.concatMapStringsSep "\n  " escape items;
    mkVal = value:
      if lib.isList value then mkList value
      else " " + (if value == true then "yes"
      else if value == false then "no"
      else toString value);
    mkEntry = name: value: "${escape name} =${mkVal value}";
    final = lib.concatStringsSep "\n" (lib.mapAttrsToList mkEntry cfg.config);
  in pkgs.writeText "postfix.cf" final;

  mkSocket = srvcfg: let
    socketPath = "${cfg.queueDir}/${srvcfg.address}";
    mode = if srvcfg.type == "fifo" then "ListenFIFO" else "ListenStream";
    addr = if srvcfg.type == "inet" then srvcfg.address else socketPath;
  in {
    description = "Postfix Service Socket '${srvcfg.name}'";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ${mode} = addr;
      MaxConnections = srvcfg.processLimit;
      Accept = true;
    };
  };

  mkService = srvcfg: {
    description = "Postfix Service '${srvcfg.name}'";
    serviceConfig.ExecStart = let
      mkArg = arg: "'${lib.escape ["'" "\\"] arg}'";
      isFullPath = builtins.substring 0 1 srvcfg.program == "/" srvcfg.program;
      postfixPath = "${postfix}/libexec/postfix/srvcfg.program";
      fullPath = if isFullPath then srvcfg.program else postfixPath;
    in toString (lib.singleton srvcfg.program ++ map mkArg srvcfg.args);
    environment = {
      MAIL_CONFIG = cfgfile;
    } // lib.optionalAttrs srvcfg.verbose {
      MAIL_VERBOSE = 1;
    } // lib.optionalAttrs srvcfg.debug {
      MAIL_DEBUG = 1;
    };
  };

in {
  options.headcounter.services.postfix = {
    enable = lib.mkEnableOption "Postfix mail server";

    user = mkOption {
      type = types.str;
      default = "postfix";
      description = ''
        The user name to use instead of the default.
        If something else than the default (<literal>postfix</literal>) is
        used, the user is not created.
      '';
    };

    group = mkOption {
      type = types.str;
      default = "postfix";
      description = ''
        The group name to use instead of the default.
        If something else than the default (<literal>postfix</literal>) is
        used, the group is not created.
      '';
    };

    services = mkOption {
      type = types.attrsOf (types.submodule serviceOptions);
      # XXX: This is not the fully fleshed out default master.cf!
      default = {
        smtpd.type = "inet";
        smtpd.address = 25;

        submission.type = "inet";
        submission.program = "smtpd";
        submission.address = 587;

        defer.program = "bounce";
        defer.processLimit = 0;

        trace.program = "bounce";
        trace.processLimit = 0;

        pickup.processLimit = 1;
        cleanup.processLimit = 0;
        qmgr.processLimit = 1;
        tlsmgr.processLimit = 1;
        rewrite.program = "trivial-rewrite";
        bounce.processLimit = 0;
        verify.processLimit = 1;
        flush.processLimit = 0;
        proxymap = {};
        proxywrite.program = "proxymap";
        smtp = {};
        relay.program = "smtp";
        relay.args = [ "-o" "smtp_fallback_relay" ];
        showq = {};
        error = {};
        retry.program = "error";
        discard = {};
        local = {};
        virtual = {};
        lmtp = {};
        anvil.processLimit = 1;
        scache.processLimit = 1;
      };
      example = {
        submission = {
          type = "inet";
          args = [ "-o" "smtpd_tls_security_level=encrypt" ];
        };
      };
      description = ''
        An attribute set of service options, which correspond to the service
        definitions usually done within the Postfix
        <filename>master.cf</filename> file.
      '';
    };

    queueDir = mkOption {
      type = types.path;
      default = "/var/lib/postfix/queue";
      description = ''
        The queue directory of Postfix, which is the base directory where
        Postfix services exchange data between each others.
      '';
    };

    defaultProcessLimit = mkOption {
      type = types.int;
      default = 100;
      description = ''
        The process limit to use whenever <option>processLimit</option> is not
        set in a Postfix service configuration.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.postfix;
      description = ''
        The Postfix derivation to use for this instance.
      '';
    };

    config = mkOption {
      type = with types;
        attrsOf (either str (either int (either bool (listOf str))));
      default = {};
      description = ''
        Configuration options (<filename>main.cf</filename>) for Postfix.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      systemd.services = mkPrefixedUnits mkService cfg.services;
      systemd.sockets = mkPrefixedUnits mkSocket cfg.services;
    })
    # TODO: Use special users for each single service
    (lib.mkIf (cfg.enable && cfg.user != "postfix") {
      users.users.postfix = {
        description = "Postfix mail server user";
        uid = config.ids.uids.postfix;
        inherit (cfg) group;
      };
    })
    (lib.mkIf (cfg.enable && cfg.group != "postfix") {
      users.groups.postfix.gid = config.ids.gids.postfix;
    })
  ];
}