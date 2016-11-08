#ifndef _METAC_FS_H
#define _METAC_FS_H
#include "metac/fs.capnp.h"

namespace metac {
namespace fs {

Filesystem::Client getLocalFilesystem();

}
}

#endif
