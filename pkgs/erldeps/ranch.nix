{ buildErlang, fetchFromGitHub }:

buildErlang rec {
  name = "ranch";
  version = "1.1.0";

  src = fetchFromGitHub {
    repo = "ranch";
    owner = "ninenines";
    rev = version;
    sha256 = "02b6nzdllrym90a5bhzlz4s52hyj9vwcn048na4j5jiivknm8g3r";
  };
}
