use crate::descriptors::Descriptors;
use crate::globals::Globals;
use fnv::FnvHashMap;
use std::fmt::{Debug, Formatter};
use std::ops::Deref;
use std::sync::{Arc, Mutex, Weak};

/// Decides whether a buffer that is given back may be kept for reuse.
type KeepFilter<Description> = fn(&Description) -> bool;

struct PoolInner<Type, Description> {
    available: Mutex<Vec<(Type, Description)>>,
    /// Buffers rejected by this filter are dropped instead of being kept.
    keep: Option<KeepFilter<Description>>,
    /// At most this many buffers are kept for reuse; more are dropped.
    max_available: usize,
}
type Constructor<Type, Description> = Box<dyn Fn(&Descriptors, &Description) -> Type>;

#[derive(Debug, Default)]
pub struct TexturePool {
    pools: FnvHashMap<TextureKey, BufferPool<(wgpu::Texture, wgpu::TextureView), AlwaysCompatible>>,
    globals_cache: FnvHashMap<GlobalsKey, Arc<Globals>>,
}

impl TexturePool {
    pub fn new() -> Self {
        Default::default()
    }

    pub fn get_texture(
        &mut self,
        descriptors: &Descriptors,
        size: wgpu::Extent3d,
        usage: wgpu::TextureUsages,
        format: wgpu::TextureFormat,
        sample_count: u32,
    ) -> PoolEntry<(wgpu::Texture, wgpu::TextureView), AlwaysCompatible> {
        let key = TextureKey {
            size,
            usage,
            format,
            sample_count,
        };
        let pool = self.pools.entry(key).or_insert_with(|| {
            let label = if cfg!(feature = "render_debug_labels") {
                use std::sync::atomic::{AtomicU32, Ordering};
                static ID_COUNT: AtomicU32 = AtomicU32::new(0);
                let id = ID_COUNT.fetch_add(1, Ordering::Relaxed);
                create_debug_label!("Pooled texture {}", id)
            } else {
                None
            };
            BufferPool::new(Box::new(move |descriptors, _description| {
                let texture = descriptors.device.create_texture(&wgpu::TextureDescriptor {
                    label: label.as_deref(),
                    size,
                    mip_level_count: 1,
                    sample_count,
                    dimension: wgpu::TextureDimension::D2,
                    format,
                    view_formats: &[format],
                    usage,
                });
                let view = texture.create_view(&Default::default());
                (texture, view)
            }))
        });
        pool.take(descriptors, AlwaysCompatible)
    }

    pub fn get_globals(
        &mut self,
        descriptors: &Descriptors,
        viewport_width: u32,
        viewport_height: u32,
    ) -> Arc<Globals> {
        self.globals_cache
            .entry(GlobalsKey {
                viewport_width,
                viewport_height,
            })
            .or_insert_with(|| {
                Arc::new(Globals::new(
                    &descriptors.device,
                    &descriptors.bind_layouts.globals,
                    viewport_width,
                    viewport_height,
                ))
            })
            .clone()
    }
}

#[derive(Copy, Clone, Debug, Hash, Eq, PartialEq)]
struct TextureKey {
    size: wgpu::Extent3d,
    usage: wgpu::TextureUsages,
    format: wgpu::TextureFormat,
    sample_count: u32,
}

#[derive(Copy, Clone, Debug, Hash, Eq, PartialEq)]
struct GlobalsKey {
    viewport_width: u32,
    viewport_height: u32,
}

pub trait BufferDescription: Clone + Debug {
    type Cost: Ord;

    /// If the potential buffer represented by this description (`self`)
    /// fits another existing buffer and its description (`other`),
    /// return the cost to use that buffer instead of making a new one.
    ///
    /// Cost is an arbitrary unit, but lower is better.
    /// None means that the other buffer cannot be used in place of this one.
    fn cost_to_use(&self, other: &Self) -> Option<Self::Cost>;
}

#[derive(Clone, Debug)]
pub struct AlwaysCompatible;

impl BufferDescription for AlwaysCompatible {
    type Cost = ();

    fn cost_to_use(&self, _other: &Self) -> Option<()> {
        Some(())
    }
}

pub struct BufferPool<Type, Description: BufferDescription> {
    available: Arc<PoolInner<Type, Description>>,
    constructor: Constructor<Type, Description>,
}

impl<Type, Description: BufferDescription> Debug for BufferPool<Type, Description> {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BufferPool").finish()
    }
}

impl<Type, Description: BufferDescription> BufferPool<Type, Description> {
    pub fn new(constructor: Constructor<Type, Description>) -> Self {
        Self::with_limits(constructor, None, usize::MAX)
    }

    /// Like `new`, but a buffer that is given back is dropped instead of
    /// being kept when `keep` rejects it or when `max_available` buffers are
    /// already kept.
    pub fn with_limits(
        constructor: Constructor<Type, Description>,
        keep: Option<KeepFilter<Description>>,
        max_available: usize,
    ) -> Self {
        Self {
            available: Arc::new(PoolInner {
                available: Mutex::new(vec![]),
                keep,
                max_available,
            }),
            constructor,
        }
    }

    pub fn take(
        &self,
        descriptors: &Descriptors,
        description: Description,
    ) -> PoolEntry<Type, Description> {
        let mut guard = self
            .available
            .available
            .lock()
            .expect("Should not be able to lock recursively");
        let mut best: Option<(Description::Cost, usize)> = None;
        for i in 0..guard.len() {
            if let Some(cost) = description.cost_to_use(&guard[i].1) {
                if let Some(best) = &mut best {
                    if best.0 > cost {
                        *best = (cost, i);
                    }
                } else if best.is_none() {
                    best = Some((cost, i));
                }
            }
        }

        let (item, used_description) = if let Some((_, best)) = best {
            guard.swap_remove(best)
        } else {
            let item = (self.constructor)(descriptors, &description);
            (item, description)
        };
        PoolEntry {
            item: Some(item),
            description: used_description,
            pool: Arc::downgrade(&self.available),
        }
    }
}

pub struct PoolEntry<Type, Description: BufferDescription> {
    item: Option<Type>,
    description: Description,
    pool: Weak<PoolInner<Type, Description>>,
}

impl<Type, Description: BufferDescription> Debug for PoolEntry<Type, Description>
where
    Type: Debug,
{
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("PoolEntry").field(&self.item).finish()
    }
}

impl<Type, Description: BufferDescription> Drop for PoolEntry<Type, Description> {
    fn drop(&mut self) {
        if let Some(item) = self.item.take()
            && let Some(pool) = self.pool.upgrade()
        {
            if pool.keep.is_some_and(|keep| !keep(&self.description)) {
                return;
            }
            let mut available = pool
                .available
                .lock()
                .expect("Should not be able to lock recursively");
            if available.len() < pool.max_available {
                available.push((item, self.description.clone()));
            }
        }
    }
}

impl<Type, Description: BufferDescription> Deref for PoolEntry<Type, Description> {
    type Target = Type;

    fn deref(&self) -> &Self::Target {
        self.item.as_ref().expect("Item should exist until dropped")
    }
}

#[cfg(test)]
mod tests {
    use super::{BufferDescription, BufferPool, PoolEntry};
    use std::sync::Arc;

    #[derive(Clone, Debug)]
    struct Size(u64);

    impl BufferDescription for Size {
        type Cost = u64;

        fn cost_to_use(&self, other: &Self) -> Option<u64> {
            other.0.checked_sub(self.0)
        }
    }

    fn give_back(pool: &BufferPool<u32, Size>, item: u32, size: u64) {
        drop(PoolEntry {
            item: Some(item),
            description: Size(size),
            pool: Arc::downgrade(&pool.available),
        });
    }

    fn kept(pool: &BufferPool<u32, Size>) -> Vec<u32> {
        let available = pool.available.available.lock().unwrap();
        available.iter().map(|(item, _)| *item).collect()
    }

    #[test]
    fn unlimited_pool_keeps_everything() {
        let pool = BufferPool::<u32, Size>::new(Box::new(|_, _| 0));
        for i in 0..5 {
            give_back(&pool, i, 1 << 30);
        }
        assert_eq!(kept(&pool), vec![0, 1, 2, 3, 4]);
    }

    #[test]
    fn limited_pool_drops_large_and_extra_buffers() {
        let pool =
            BufferPool::<u32, Size>::with_limits(Box::new(|_, _| 0), Some(|s| s.0 <= 100), 2);
        give_back(&pool, 1, 101);
        give_back(&pool, 2, 100);
        give_back(&pool, 3, 10);
        give_back(&pool, 4, 10);
        assert_eq!(kept(&pool), vec![2, 3]);
    }
}
