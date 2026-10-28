# -*- coding: utf-8 -*-
import json
import pathlib

base = pathlib.Path(r"C:\Users\Administrator\Desktop\diary\src\i18n\locales")
data = {
    "en.json": (
        "Account deletion",
        "You can delete your account from the in-app Account menu. If you cannot open the app, see the <deletionLink>account and data deletion page</deletionLink> or contact the developer via Google Play.",
    ),
    "ja.json": (
        "アカウント削除",
        "アプリのアカウントメニューから退会できます。アプリを開けない場合は、<deletionLink>アカウントとデータの削除案内</deletionLink>を確認するか、Playの開発者連絡先へ依頼してください。",
    ),
    "zh.json": (
        "账号删除",
        "可在应用的账号菜单中注销。无法打开应用时，请查看<deletionLink>账号与数据删除说明</deletionLink>，或通过 Play 上的开发者联系方式申请。",
    ),
    "zh-TW.json": (
        "帳號刪除",
        "可在應用程式的帳號選單中刪除帳號。無法開啟應用程式時，請查看<deletionLink>帳號與資料刪除說明</deletionLink>，或透過 Play 上的開發者聯絡方式申請。",
    ),
    "es.json": (
        "Eliminación de la cuenta",
        "Puedes eliminar tu cuenta desde el menú Cuenta de la app. Si no puedes abrirla, consulta la <deletionLink>página de eliminación de cuenta y datos</deletionLink> o contacta al desarrollador en Play.",
    ),
    "pt.json": (
        "Exclusão da conta",
        "Você pode excluir a conta no menu Conta do app. Se não conseguir abrir o app, veja a <deletionLink>página de exclusão da conta e dos dados</deletionLink> ou fale com o desenvolvedor na Play.",
    ),
    "fr.json": (
        "Suppression du compte",
        "Vous pouvez supprimer votre compte depuis le menu Compte de l'app. Si vous ne pouvez pas l'ouvrir, consultez la <deletionLink>page de suppression du compte et des données</deletionLink> ou contactez le développeur via Play.",
    ),
    "de.json": (
        "Kontolöschung",
        "Du kannst dein Konto im Kontomenü der App löschen. Wenn du die App nicht öffnen kannst, sieh dir die <deletionLink>Seite zur Konto- und Datenlöschung</deletionLink> an oder kontaktiere den Entwickler über Play.",
    ),
    "vi.json": (
        "Xóa tài khoản",
        "Bạn có thể xóa tài khoản trong menu Tài khoản của ứng dụng. Nếu không mở được ứng dụng, xem <deletionLink>trang xóa tài khoản và dữ liệu</deletionLink> hoặc liên hệ nhà phát triển trên Play.",
    ),
    "th.json": (
        "การลบบัญชี",
        "ลบบัญชีได้จากเมนูบัญชีในแอป หากเปิดแอปไม่ได้ ดูที่ <deletionLink>หน้ารายละเอียดการลบบัญชีและข้อมูล</deletionLink> หรือติดต่อนักพัฒนาผ่าน Play",
    ),
    "id.json": (
        "Penghapusan akun",
        "Anda dapat menghapus akun dari menu Akun di aplikasi. Jika aplikasi tidak bisa dibuka, lihat <deletionLink>halaman penghapusan akun dan data</deletionLink> atau hubungi pengembang lewat Play.",
    ),
}

for name, (heading, body) in data.items():
    path = base / name
    obj = json.loads(path.read_text(encoding="utf-8"))
    legal = obj["appInfo"]["legal"]
    if "accountDeletionHeading" in legal:
        print("skip", name)
        continue
    new = {}
    for key, value in legal.items():
        if key == "refundHeading":
            new["accountDeletionHeading"] = heading
            new["accountDeletionBody"] = body
        new[key] = value
    obj["appInfo"]["legal"] = new
    path.write_text(
        json.dumps(obj, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print("ok", name)
