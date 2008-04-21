# Author: Julien MISCHKOWITZ <wain@archlinux.fr>
pkgname=yaourt
pkgver=0.9
pkgrel=1
pkgdesc="A Pacman frontend with more features and AUR support" 
arch=(i686 x86_64 ppc)
url="http://www.archlinux.fr/yaourt-en/" 
license="GPL" 
depends=('wget' 'diffutils' 'pacman>=3.1.0') 
conflicts=('bash-completion-yaourt')
replaces=('bash-completion-yaourt')
install=yaourt.install
backup=('etc/yaourtrc')
source=(http://archiwain.free.fr/os/i686/$pkgname/$pkgname-$pkgver.src.tar.gz) 
md5sums=('6b280a549e8157105e624581cc54e56f')

build() { 
	cd $startdir/src/$pkgname 
	make install DESTDIR=$pkgdir || return 1
}
