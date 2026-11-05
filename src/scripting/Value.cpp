#include "Value.h"
#include <iomanip>
#include <sstream>
namespace Argon::Scripting {
std::string Value::toString() const {
    if (isNull()) return "null";
    if (isBoolean()) return asBoolean() ? "true" : "false";
    if (isString()) return asString();
    std::ostringstream stream;
    stream << std::setprecision(15) << asNumber();
    return stream.str();
}
} // namespace Argon::Scripting
