#ifndef _METAC_OSTOOLS_H
#define _METAC_OSTOOLS_H
#include <string>
#include <kj/memory.h>

namespace metac {

bool fileExists(std::string path);
void createDir(std::string path);
void unlink(std::string path);
std::string randomHexString(int length=32);
}
#endif
