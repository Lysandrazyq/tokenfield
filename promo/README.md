# 宣传片

`promo/film.html` 是一个按时间 t 绘制任意一帧的网页（确定性：没有实时时钟，所有动效都是 t 的纯函数）。
`promo/render.mjs` 用无头 Chrome 逐帧截图，`promo/audio.mjs` 生成配乐，最后 ffmpeg 合成。

```bash
node promo/render.mjs landscape   # 1920×1080 → promo/out/tokenfield-16x9.mp4
node promo/render.mjs portrait    # 1080×1920 → promo/out/tokenfield-9x16.mp4
```

预览：浏览器打开 `promo/film.html?t=4.2&layout=landscape` 看某一帧；去掉 `t` 参数会实时播放。
