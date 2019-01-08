{fetchgit, ...}:
{
  backplane = fetchgit {
    name = "backplane";
    url = "https://github.com/metacontainer/backplane";
    rev = "7b11031e041e7e720b54499599a6bdb861dba294";
    fetchSubmodules = true;
    sha256 = "0l05w6vb0hqcl87ndklzxaj2sqi7kpd8qfy5424nz5gvnvl27a2h";
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
    rev = "66f46632dbb72bb989fbacf728ea640f341292d4";
    fetchSubmodules = true;
    sha256 = "1r09avl1naa1mjwhsppsy980wsdwi7m84qw0r8qlm13s5c05fl3g";
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
    rev = "698ac0645e12f3cac34ba2523248d7d2781f613a";
    fetchSubmodules = true;
    sha256 = "0cwqmac77lsmpl5znwm2jap4gc2f6zgyjjz5l54mp669jcchvvyx";
  };
  sctp = fetchgit {
    name = "sctp";
    url = "https://github.com/metacontainer/sctp.nim";
    rev = "fe0438d989b1d6fa12ac0a8bd9eb9ac9699b3b1b";
    fetchSubmodules = true;
    sha256 = "10db9zv1p26qq6myqc3d7ldbwisfa8rr162g6j6dbw4349adjxa9";
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
    rev = "25b78aca10c9751f9928fb5f74792e67d14c7e5e";
    fetchSubmodules = true;
    sha256 = "0a4h76m518b5ax97f7158mlmlkhyjnaq6cn0qx5cgppr9dfbdxc1";
  };
}
