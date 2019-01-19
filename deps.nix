{fetchgit, ...}:
{
  backplane = fetchgit {
    name = "backplane";
    url = "https://github.com/metacontainer/backplane";
    rev = "5d583bb941d48873908756aad0db5fda1fc79002";
    fetchSubmodules = true;
    sha256 = "0dyb7632v0w2r10y6hmnhmhfmzp99h2yi5hivjim72598rgwcdab";
  };
  channelguard = fetchgit {
    name = "channelguard";
    url = "https://github.com/zielmicha/channelguard";
    rev = "7d7456e6cfd5d886abd387252ab0ec88dba78b71";
    fetchSubmodules = true;
    sha256 = "1555mfapb8pha9n81n25x4r86c3wkbp1rb21lphxfzfys6jv7xwd";
  };
  cligen = fetchgit {
    name = "cligen";
    url = "https://github.com/metacontainer/cligen";
    rev = "b1b4267122d7d1a6b34d422fe306d78bb32cc251";
    fetchSubmodules = true;
    sha256 = "0x7751a2q5dnhzsr63d1q9jnzavsxvh3lqr11ddwcmqyb6zjgc4l";
  };
  collections = fetchgit {
    name = "collections";
    url = "https://github.com/zielmicha/collections.nim";
    rev = "a6b3a024c95390adb6d95549471b14af9a515efc";
    fetchSubmodules = true;
    sha256 = "0xrzgr51dw1hjcnksvb1j8bkx4sw9v3bgvgmw726qapnd1kjck1k";
  };
  reactor = fetchgit {
    name = "reactor";
    url = "https://github.com/zielmicha/reactor.nim";
    rev = "96976e023f2fba66f9ae947d0d193d7a1b10867f";
    fetchSubmodules = true;
    sha256 = "14fav8r80bs5lilvrx1cp3yl7gydx3zl7h7ajs73i4l01fs3y5xx";
  };
  sctp = fetchgit {
    name = "sctp";
    url = "https://github.com/metacontainer/sctp.nim";
    rev = "d207c3ec1485252a25886cde6075cadaeae5d5de";
    fetchSubmodules = true;
    sha256 = "13xlhj2wf85pvh20kpcgbhh70cjmywdiyglypq5a07c52cy18m8a";
  };
  sodium = fetchgit {
    name = "sodium";
    url = "https://github.com/zielmicha/libsodium.nim";
    rev = "e1c88906d5958ffe56ee2590d34fdc8b2f3a96f5";
    fetchSubmodules = true;
    sha256 = "1ymzrxb0i7fhrzrfbrvpcbbxn7qj0s9sgf2pkraq79gaaghq62z3";
  };
  xrest = fetchgit {
    name = "xrest";
    url = "https://github.com/zielmicha/xrest";
    rev = "4bf8ba8605e14410087c7054e2ade75e8f4c6e64";
    fetchSubmodules = true;
    sha256 = "1xzr4hlaikcs4k69gfm68sfm06varpj89pkprkzd7v0bn5is7wsj";
  };
}
