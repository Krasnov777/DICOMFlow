# DICOMFlow Landing Page

Professional landing page for dicomflow.org

## Features

- Modern, responsive design
- Auto-detects user's OS for download recommendations
- Fast loading (no build step required)
- SEO optimized
- Mobile-friendly

## Deployment Options

### Option 1: GitHub Pages (Recommended)

1. **Enable GitHub Pages:**
   - Go to your repository settings
   - Navigate to "Pages" section
   - Source: Deploy from a branch
   - Branch: `main`
   - Folder: `/website`
   - Save

2. **Configure Custom Domain:**
   - Add `CNAME` file with your domain: `dicomflow.org`
   - In your domain registrar (where you bought dicomflow.org):
     - Add CNAME record: `www` → `krasnov777.github.io`
     - Add A records for apex domain:
       ```
       185.199.108.153
       185.199.109.153
       185.199.110.153
       185.199.111.153
       ```

3. **Wait for DNS propagation** (5-30 minutes)

4. **Enable HTTPS** in GitHub Pages settings

### Option 2: Netlify

1. **Sign up at netlify.com**
2. **Drag and drop the `website` folder**
3. **Configure custom domain:**
   - Site settings → Domain management
   - Add custom domain: `dicomflow.org`
   - Follow Netlify's DNS instructions

### Option 3: Vercel

1. **Sign up at vercel.com**
2. **Import from GitHub**
3. **Set root directory** to `website`
4. **Add custom domain** in project settings

## Local Preview

Simply open `index.html` in your browser:

```bash
cd website
open index.html
```

Or use a simple HTTP server:

```bash
# Python 3
python3 -m http.server 8000

# Node.js (if you have npx)
npx serve

# Then open http://localhost:8000
```

## Customization

### Update Download Links

When you create new releases, the download buttons automatically point to:
`https://github.com/Krasnov777/DICOMFlow/releases/latest`

This always redirects to the newest release.

### Add Screenshots

1. Take screenshots of your app
2. Save them in `website/images/`
3. Update the hero section or add a screenshots section

### Update Version Number

Search for "0.1.0" in `index.html` and update to your current version.

## SEO

The page includes:
- Meta descriptions
- Keywords
- Semantic HTML
- Fast loading time
- Mobile responsive

## Performance

- No build step required
- Tailwind CSS via CDN (production should use build)
- Minimal JavaScript
- Fast load times

## Future Enhancements

- Add screenshot carousel
- Add testimonials section
- Add blog for updates
- Add contact form
- Use built Tailwind CSS instead of CDN
