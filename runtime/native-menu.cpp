// Local Qt extension for the AudaDockBar launcher. No polling or autostart.
#include <QApplication>
#include <QMenu>
#include <QAction>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QPointer>
#include <QTimer>
#include <QSignalBlocker>
#include <QWindowStateChangeEvent>
#include <QDateTime>
#include <libintl.h>
#include <QDBusVirtualObject>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QJsonArray>
#include <QVector>
#include <libaudcore/playlist.h>

static QString normalized(QString text) {
    return text.remove('&').remove('_').trimmed().toLower();
}
static bool viewLabel(const QString &label) {
    const auto title = normalized(label);
    return title == normalized(QString::fromUtf8(dgettext("audacious-plugins", "View")))
        || title == "view" || title == "ansicht";
}
static bool isView(QMenu *menu) {
    if (viewLabel(menu->menuAction()->text())) return true;
    // Audacious uses separate MenuAction objects; the submenu itself has no title.
    for (auto widget : QApplication::allWidgets())
        for (auto action : widget->actions())
            if (action->menu() == menu && viewLabel(action->text())) return true;
    return false;
}
static bool docked() {
    QFile file(qEnvironmentVariable("HOME") + "/.config/audacious/adb.json");
    if (!file.open(QIODevice::ReadOnly)) return true;
    return QJsonDocument::fromJson(file.readAll()).object().value("docked").toBool(true);
}
static void requestDock(bool checked) {
QProcess command;
auto env = QProcessEnvironment::systemEnvironment();
// The extension belongs inside Audacious, not in IPC helpers.
auto preload = env.value("LD_PRELOAD");
preload.remove(qEnvironmentVariable("HOME") + "/.local/share/adb/native-menu.so");
if (preload.trimmed().isEmpty()) env.remove("LD_PRELOAD");
else env.insert("LD_PRELOAD", preload.trimmed());
command.setProcessEnvironment(env);
command.setProgram("omarchy-shell");
command.setArguments({"adb.audadockbar", "dock", checked ? "true" : "false"});
if (!command.startDetached()) qWarning("Audacious dock: could not start omarchy-shell");
}
class DockMenuFilter : public QObject {
    QList<QPointer<QAction>> entries;
public:
    explicit DockMenuFilter(QObject *parent) : QObject(parent) {}
    ~DockMenuFilter() override { for (auto action : entries) if (action) delete action; }
    bool eventFilter(QObject *obj, QEvent *event) override {
        if (event->type() == QEvent::WindowStateChange) {
            auto window = qobject_cast<QWidget *>(obj);
            auto change = static_cast<QWindowStateChangeEvent *>(event);
            // The Winamp player's minimize button calls QWidget::showMinimized.
            // Match only the frameless main player, not dialogs or auxiliary panels.
            if (window && window->isWindow()
                && (window->windowFlags() & Qt::FramelessWindowHint)
                && (window->windowFlags() & Qt::WindowMinimizeButtonHint)
                && (window->windowState() & Qt::WindowMinimized)
                && !(change->oldState() & Qt::WindowMinimized)) {
                const auto oldState = change->oldState();
                const auto now = QDateTime::currentMSecsSinceEpoch();
                const bool request = now - window->property("adbLastFastDock").toLongLong() > 250;
                if (request) window->setProperty("adbLastFastDock", now);
                QTimer::singleShot(0, window, [window, oldState, request] {
                    window->setWindowState(oldState);
                    if (request) requestDock(true);
                });
                return true;
            }
        }
        if (event->type() != QEvent::Show && event->type() != QEvent::Polish)
            return false;
        auto menu = qobject_cast<QMenu *>(obj);
        if (!menu) return false;
        // Decorate the View submenu before its parent menu opens, so its geometry
        // already includes the checkbox when Qt calculates the popup position.
        for (auto action : menu->actions()) {
            if (action->menu() && viewLabel(action->text())) {
                QEvent polish(QEvent::Polish);
                eventFilter(action->menu(), &polish);
            }
        }
        if (!isView(menu)) return false;
        auto action = menu->findChild<QAction *>("adb-dock-mode", Qt::FindDirectChildrenOnly);
        if (!action) {
            action = new QAction("Dock mode", menu);
            action->setObjectName("adb-dock-mode");
            action->setCheckable(true);
            menu->insertAction(menu->actions().value(0), action);
            entries.append(action);
            QObject::connect(action, &QAction::triggered, action, [](bool checked) {
                requestDock(checked);
            });
            QObject::connect(menu, &QMenu::aboutToShow, action, [action] {
                QSignalBlocker block(action);
                action->setChecked(docked());
            });
        }
        QSignalBlocker block(action);
        action->setChecked(docked());
        return false;
    }
};
class PlaylistReorder : public QDBusVirtualObject {
public:
    explicit PlaylistReorder(QObject *parent) : QDBusVirtualObject(parent) {}
    QString introspect(const QString &) const override {
        return "<interface name=\"org.adb.AudaDockBar\"><method name=\"MoveEntry\"><arg type=\"s\" direction=\"in\"/><arg type=\"b\" direction=\"out\"/></method></interface>";
    }
    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override {
        if (message.interface() != "org.adb.AudaDockBar" || message.member() != "MoveEntry") return false;
        auto fail = [&](const QString &reason) {
            connection.send(message.createErrorReply("org.adb.AudaDockBar.StalePlaylist", reason));
            return true;
        };
        if (message.arguments().size() != 1 || message.signature() != "s") return fail("Invalid move request.");
        const auto request = QJsonDocument::fromJson(message.arguments()[0].toString().toUtf8()).object();
        const int playlistIndex = request.value("playlist").toInt(-1);
        auto playlist = Playlist::active_playlist();
        if (!playlist.exists() || playlist.index() != playlistIndex
            || QString::fromUtf8(static_cast<const char *>(playlist.get_title())) != request.value("name").toString())
            return fail("The playlist changed. Please try again.");
        const auto uris = request.value("uris").toArray();
        const int count = playlist.n_entries();
        const int from = request.value("from").toInt(-1), to = request.value("to").toInt(-1);
        if (uris.size() != count || from < 0 || to < 0 || from >= count || to >= count)
            return fail("The playlist entries changed. Please try again.");
        for (int index = 0; index < count; ++index)
            if (QString::fromUtf8(static_cast<const char *>(playlist.entry_filename(index))) != uris[index].toString())
                return fail("The playlist order changed. Please try again.");
        if (from != to) {
            QVector<bool> selected(count);
            for (int index = 0; index < count; ++index) selected[index] = playlist.entry_selected(index);
            const int focus = playlist.get_focus();
            playlist.select_all(false);
            playlist.select_entry(from, true);
            playlist.shift_entries(from, to - from);
            auto newIndex = [&](int old) {
                if (old == from) return to;
                if (from < to && old > from && old <= to) return old - 1;
                if (from > to && old >= to && old < from) return old + 1;
                return old;
            };
            playlist.select_all(false);
            for (int index = 0; index < count; ++index)
                if (selected[index]) playlist.select_entry(newIndex(index), true);
            playlist.set_focus(newIndex(focus));
        }
        connection.send(message.createReply(QVariantList{true}));
        return true;
    }
};
static void installDockMenu() {
    QTimer::singleShot(0, QCoreApplication::instance(), [] {
        auto bus = QDBusConnection::sessionBus();
        if (bus.registerService("org.adb.AudaDockBar"))
            bus.registerVirtualObject("/org/adb/AudaDockBar", new PlaylistReorder(QCoreApplication::instance()));
        if (auto app = qobject_cast<QApplication *>(QCoreApplication::instance()))
            app->installEventFilter(new DockMenuFilter(app));
    });
}
Q_COREAPP_STARTUP_FUNCTION(installDockMenu)
