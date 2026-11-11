# Offline website QR generator

Ticket QR rendering bundles the website `apps/frontend/src/components/islands/qr-generator/qr-render.ts` and qrcode 1.5.4 in `WebsiteTicketQR` (TicketsView.swift). It uses the same cropped logo, version 10 minimum, 70% preferred logo size reduced down to 15% within the website error-correction budget, four-module margin and light brand palette. The HTML has a restrictive content policy and nonpersistent storage. Tokens are passed as JavaScript arguments and never interpolated into HTML or sent over the network.

The website renderer is compiled for the browser using esbuild. The React generator controls are replaced by a local canvas preparation and rendering entry point; the matrix, module forcing, color sampling and SVG renderer come from the website source. The qrcode MIT license is included alongside this file. Physical scanner verification remains required for the final ticket rendering.
