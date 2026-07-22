#ifndef DAU_CONFIG_H
#define DAU_CONFIG_H

#include <fcitx-config/configuration.h>
#include <fcitx-config/enum.h>
#include <fcitx-config/option.h>
#include <fcitx-utils/i18n.h>
#include <fcitx-utils/log.h>

// Log category "dau" — define once in dau_engine.cpp.
FCITX_DECLARE_LOG_CATEGORY(dau_log);

namespace dau {

// fcitx5 config types (Option, OptionWithAnnotation, Configuration) live in
// namespace fcitx; bring them in so FCITX_CONFIGURATION expands cleanly here.
using namespace fcitx;

// GUI method choice (fcitx5 config). Distinct from C ABI DauMethod.
enum class DauConfigMethod {
    Telex = 0,
    VNI = 1,
};

FCITX_CONFIG_ENUM_NAME_WITH_I18N(DauConfigMethod, N_("Telex"), N_("VNI"));

// fcitx5 configuration descriptor for fcitx5-configtool.
// File on disk: ~/.config/fcitx5/conf/dau.conf
// Source of truth for method / enabled / autoCapitalize / autoRestore.
// TOML (~/.config/dau/config.toml) remains for shortcuts + per-app strategy.
FCITX_CONFIGURATION(
    DauConfig,
    OptionWithAnnotation<DauConfigMethod, DauConfigMethodI18NAnnotation>
        method{this, "Method", _("Kiểu gõ"), DauConfigMethod::Telex};
    Option<bool> enabled{this, "Enabled", _("Bật bộ gõ"), true};
    Option<bool> autoCapitalize{this, "AutoCapitalize",
                                _("Tự viết hoa đầu câu"), false};
    Option<bool> autoRestore{this, "AutoRestore",
                             _("Tự phục hồi khi gõ sai"), true};);

} // namespace dau

#endif // DAU_CONFIG_H
